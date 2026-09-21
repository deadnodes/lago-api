# frozen_string_literal: true

require "base64"

module Emails
  class PosterService < BaseService
    Result = BaseResult

    def self.configured?
      ActiveModel::Type::Boolean.new.cast(ENV["LAGO_POSTER_ENABLED"]) &&
        ENV["LAGO_POSTER_API_URL"].present? &&
        ENV["LAGO_POSTER_API_TOKEN"].present?
    end

    def initialize(invoice:, to: nil, cc: nil, bcc: nil)
      @invoice = invoice
      @to = to
      @cc = cc
      @bcc = bcc

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "invoice_not_finalized") unless invoice.finalized?
      return result.forbidden_failure!(code: "poster_not_configured") unless self.class.configured?

      message = InvoiceMailer.with(mailer_params).created.message
      return result.validation_failure!(errors: {invoice: ["could not render invoice email"]}) unless message

      recipients = [message.to, message.cc, message.bcc].flat_map { |addresses| Array(addresses) }.compact_blank.map(&:to_s).uniq
      return result.validation_failure!(errors: {to: ["must have at least one recipient"]}) if recipients.empty?

      attachments = message.attachments.map { |attachment| serialize_attachment(attachment) }
      if attachments.none? { |attachment| attachment[:content_type] == "application/pdf" }
        return result.validation_failure!(errors: {invoice: ["must have a generated PDF"]})
      end

      client.post(payload(message, recipients, attachments), headers)
      result
    rescue LagoHttpClient::HttpError => error
      raise RetriableError if LagoHttpClient::Client::RETRYABLE_HTTP_STATUSES.include?(error.error_code.to_i)

      raise
    rescue *LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES
      raise RetriableError
    end

    private

    attr_reader :invoice, :to, :cc, :bcc

    def client
      @client ||= LagoHttpClient::Client.new(
        endpoint,
        open_timeout: ENV.fetch("LAGO_POSTER_OPEN_TIMEOUT", "5").to_i,
        read_timeout: ENV.fetch("LAGO_POSTER_READ_TIMEOUT", "30").to_i,
        retry_on_transient_errors: true
      )
    end

    def endpoint
      "#{ENV.fetch("LAGO_POSTER_API_URL").chomp("/")}/api/v1/emails"
    end

    def headers
      [{"Authorization" => "Bearer #{ENV.fetch("LAGO_POSTER_API_TOKEN")}"}]
    end

    def mailer_params
      {invoice:}.tap do |params|
        params[:to] = to if to
        params[:cc] = cc if cc
        params[:bcc] = bcc if bcc
      end
    end

    def payload(message, recipients, attachments)
      {
        campaign: "lago-invoice",
        recipients: recipients.map { |email| {email:, name: invoice.customer.name.to_s} },
        subject: message.subject.to_s,
        body_text: body_text(message),
        body_html: body_html(message),
        context: {
          invoice_id: invoice.id,
          invoice_number: invoice.number,
          customer_id: invoice.customer.id
        },
        attachments:,
        idempotency_key_prefix: "lago-invoice:#{invoice.id}:v#{invoice.version_number}"
      }
    end

    def body_text(message)
      message.text_part&.body&.decoded || message.body.decoded
    end

    def body_html(message)
      message.html_part&.body&.decoded || body_text(message)
    end

    def serialize_attachment(attachment)
      {
        filename: attachment.filename.to_s,
        content_type: attachment.content_type.to_s,
        content_base64: Base64.strict_encode64(attachment.body.decoded)
      }
    end
  end
end
