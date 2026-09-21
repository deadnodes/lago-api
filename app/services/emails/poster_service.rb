# frozen_string_literal: true

require "base64"

module Emails
  class PosterService < BaseService
    Result = BaseResult

    def self.configured?
      ActiveModel::Type::Boolean.new.cast(ENV["LAGO_POSTER_ENABLED"]) == true &&
        ENV["LAGO_POSTER_API_URL"].present? &&
        ENV["LAGO_POSTER_API_TOKEN"].present?
    end

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "invoice_not_finalized") unless invoice.finalized?
      return result.forbidden_failure!(code: "poster_not_configured") unless self.class.configured?

      message = InvoiceMailer.with(invoice:).finalized.message
      recipients = Array(message&.to).compact_blank
      return result.validation_failure!(errors: {to: ["must have at least one recipient"]}) if recipients.empty?

      attachments = message.attachments.map { |attachment| serialize_attachment(attachment) }
      unless attachments.any? { |attachment| attachment[:content_type].start_with?("application/pdf") }
        return result.validation_failure!(errors: {invoice: ["must have a generated PDF"]})
      end

      client.post(payload(message, recipients, attachments), headers)
      result
    rescue LagoHttpClient::HttpError => error
      raise RetriableError if error.error_code.to_i == 408 || error.error_code.to_i == 429 || error.error_code.to_i >= 500

      raise
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, SocketError
      raise RetriableError
    end

    private

    attr_reader :invoice

    def client
      @client ||= LagoHttpClient::Client.new(
        "#{ENV.fetch("LAGO_POSTER_API_URL").chomp("/")}/api/v1/emails",
        open_timeout: ENV.fetch("LAGO_POSTER_OPEN_TIMEOUT", "5").to_i,
        read_timeout: ENV.fetch("LAGO_POSTER_READ_TIMEOUT", "30").to_i
      )
    end

    def headers
      [{"Authorization" => "Bearer #{ENV.fetch("LAGO_POSTER_API_TOKEN")}"}]
    end

    def payload(message, recipients, attachments)
      {
        campaign: "lago-invoice",
        recipients: recipients.map { |email| {email:, name: invoice.customer.name.to_s} },
        subject: message.subject.to_s,
        body_text: message.text_part&.body&.decoded || message.body.decoded,
        body_html: message.html_part&.body&.decoded || message.body.decoded,
        context: {
          invoice_id: invoice.id,
          invoice_number: invoice.number,
          customer_id: invoice.customer.id
        },
        attachments:,
        idempotency_key_prefix: "lago-invoice:#{invoice.id}:v#{invoice.version_number}"
      }
    end

    def serialize_attachment(attachment)
      {
        filename: attachment.filename.to_s,
        content_type: attachment.mime_type.to_s,
        content_base64: Base64.strict_encode64(attachment.body.decoded)
      }
    end
  end
end
