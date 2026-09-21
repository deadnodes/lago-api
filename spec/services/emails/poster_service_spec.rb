# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::PosterService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice, status: :finalized, fees_amount_cents: 1000) }
  let(:poster_client) { instance_double(LagoHttpClient::Client) }
  let(:mailer_delivery) { double(message:) }
  let(:parameterized_mailer) { double(finalized: mailer_delivery) }
  let(:text_body) { double(decoded: "Invoice body") }
  let(:html_body) { double(decoded: "<p>Invoice body</p>") }
  let(:attachment_body) { double(decoded: "%PDF-1.7") }
  let(:attachment) do
    double(filename: "invoice-123.pdf", mime_type: "application/pdf", body: attachment_body)
  end
  let(:message) do
    double(
      to: [invoice.customer.email],
      subject: "Invoice INV-123",
      text_part: double(body: text_body),
      html_part: double(body: html_body),
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
    allow(LagoHttpClient::Client).to receive(:new).and_return(poster_client)
    allow(poster_client).to receive(:post).and_return({"created" => 1})
  end

  it "queues a finalized invoice with its PDF in Poster" do
    expect(result).to be_success
    expect(poster_client).to have_received(:post).with(
      hash_including(
        topic: "lago_invoice",
        recipient: {
          recipient_ref: "lago-customer:#{invoice.customer.id}",
          email: invoice.customer.email,
          name: invoice.customer.name.to_s
        },
        subject: "Invoice INV-123",
        body_text: "Invoice body",
        body_html: "<p>Invoice body</p>",
        idempotency_key: "lago-invoice:#{invoice.id}:v#{invoice.version_number}:r0",
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
    expect(LagoHttpClient::Client).to have_received(:new).with(
      "https://poster.example.internal/api/v1/notifications/email",
      anything
    )
  end

  it "retries a transient Poster response" do
    allow(poster_client).to receive(:post).and_raise(LagoHttpClient::HttpError.new(503, "unavailable", nil))
    expect { result }.to raise_error(RetriableError)
  end

  it "does not enqueue a message without a PDF" do
    allow(message).to receive(:attachments).and_return([])
    expect(result.error).to be_a(BaseService::ValidationFailure)
    expect(poster_client).not_to have_received(:post)
  end

  context "when the integration is disabled" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_POSTER_ENABLED" => "false")) }

    it "does not call Poster" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(poster_client).not_to have_received(:post)
    end
  end

  context "when the integration is enabled without a token" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_POSTER_API_TOKEN" => "")) }

    it "fails without enqueueing an email" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(poster_client).not_to have_received(:post)
    end
  end
end
