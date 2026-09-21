# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::NotifyJob do
  subject { described_class.perform_now(invoice:) }

  let(:invoice) { create(:invoice) }

  it "sends email" do
    expect { subject }.to have_enqueued_mail(InvoiceMailer, :finalized)
      .with(params: {invoice:}, args: [])
  end

  context "when Poster is enabled" do
    before do
      allow(Emails::PosterService).to receive(:enabled?).and_return(true)
      allow(Emails::PosterService).to receive(:call!)
    end

    it "delegates invoice delivery to Poster" do
      subject
      expect(Emails::PosterService).to have_received(:call!).with(invoice:)
    end
  end

  context "when Poster is enabled without credentials" do
    before do
      allow(Emails::PosterService).to receive(:enabled?).and_return(true)
      allow(Emails::PosterService).to receive(:call!).and_raise(BaseService::ForbiddenFailure.new(nil, code: "poster_not_configured"))
      allow(InvoiceMailer).to receive(:with)
    end

    it "fails closed instead of falling back to Lago email" do
      expect { subject }.to raise_error(BaseService::ForbiddenFailure)
      expect(InvoiceMailer).not_to have_received(:with)
    end
  end
end
