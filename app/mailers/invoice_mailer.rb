# frozen_string_literal: true

class InvoiceMailer < ApplicationMailer
  before_action :ensure_pdf

  def finalized
    @invoice = params[:invoice]
    @billing_entity = @invoice.billing_entity
    @customer = @invoice.customer
    @show_lago_logo = !@billing_entity.organization.remove_branding_watermark_enabled?

    return if @billing_entity.email.blank? && !Emails::PosterService.configured?
    return if @customer.email.blank?
    return if @invoice.fees_amount_cents.zero?

    I18n.locale = @customer.preferred_document_locale

    if @pdfs_enabled
      @invoice.file.open do |file|
        attachments["invoice-#{@invoice.number}.pdf"] = file.read
      end
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(from_email_address, @billing_entity.name),
        reply_to: email_address_with_name(@billing_entity.email.presence || from_email_address, @billing_entity.name),
        subject: I18n.t(
          "email.invoice.finalized.subject",
          billing_entity_name: @billing_entity.name,
          invoice_number: @invoice.number
        )
      )
    end
  end

  private

  def from_email_address
    return @billing_entity.from_email_address if @billing_entity.from_email_address.present?
    return "no-reply@poster.invalid" if Emails::PosterService.configured?

    @billing_entity.from_email_address
  end

  def ensure_pdf
    invoice = params[:invoice]

    Invoices::GeneratePdfService.new(invoice:).call
  end
end
