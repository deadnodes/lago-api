# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::NotifyJob do
  subject { described_class.perform_now(invoice:) }

  let(:invoice) { create(:invoice) }

  it "sends email" do
    expect { subject }.to have_enqueued_mail(InvoiceMailer, :created)
      .with(params: {invoice:}, args: [])
  end

  context "when Poster is configured" do
    before do
      allow(Emails::PosterService).to receive(:configured?).and_return(true)
      allow(Emails::PosterService).to receive(:call!)
    end

    it "delegates invoice delivery to Poster" do
      subject

      expect(Emails::PosterService).to have_received(:call!).with(invoice:, to: nil, cc: nil, bcc: nil)
    end
  end
end
