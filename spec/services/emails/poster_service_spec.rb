# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::PosterService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice, status: :finalized, fees_amount_cents: 1000) }
  let(:poster_client) { instance_double(LagoHttpClient::Client) }
  let(:parameterized_mailer) { instance_double(ActionMailer::Parameterized::Mailer) }
  let(:mailer_delivery) { instance_double(ActionMailer::MessageDelivery) }
  let(:text_body) { instance_double(Mail::Body, decoded: "Invoice body") }
  let(:html_body) { instance_double(Mail::Body, decoded: "<p>Invoice body</p>") }
  let(:attachment_body) { instance_double(Mail::Body, decoded: "%PDF-1.7") }
  let(:attachment) do
    instance_double(
      Mail::Part,
      filename: "invoice-123.pdf",
      content_type: "application/pdf",
      body: attachment_body
    )
  end
  let(:message) do
    instance_double(
      Mail::Message,
      to: [invoice.customer.email],
      cc: [],
      bcc: [],
      subject: "Invoice INV-123",
      text_part: instance_double(Mail::Part, body: text_body),
      html_part: instance_double(Mail::Part, body: html_body),
      attachments: [attachment]
    )
  end

  before do
    stub_const(
      "ENV",
      ENV.to_h.merge(
        "LAGO_POSTER_ENABLED" => "true",
        "LAGO_POSTER_API_URL" => "https://poster.example.internal",
        "LAGO_POSTER_API_TOKEN" => "poster-token"
      )
    )
    allow(InvoiceMailer).to receive(:with).and_return(parameterized_mailer)
    allow(parameterized_mailer).to receive(:created).and_return(mailer_delivery)
    allow(mailer_delivery).to receive(:message).and_return(message)
    allow(LagoHttpClient::Client).to receive(:new).and_return(poster_client)
    allow(poster_client).to receive(:post).and_return({"created" => 1})
  end

  it "queues the rendered invoice and PDF in Poster" do
    expect(result).to be_success

    expect(poster_client).to have_received(:post).with(
      hash_including(
        campaign: "lago-invoice",
        subject: "Invoice INV-123",
        body_text: "Invoice body",
        body_html: "<p>Invoice body</p>",
        idempotency_key_prefix: "lago-invoice:#{invoice.id}:v#{invoice.version_number}",
        attachments: [
          {
            filename: "invoice-123.pdf",
            content_type: "application/pdf",
            content_base64: Base64.strict_encode64("%PDF-1.7")
          }
        ]
      ),
      [{"Authorization" => "Bearer poster-token"}]
    )
  end

  context "when the Poster integration is disabled" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_POSTER_ENABLED" => "false")) }

    it "reports that Poster is not configured" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("poster_not_configured")
    end
  end
end
