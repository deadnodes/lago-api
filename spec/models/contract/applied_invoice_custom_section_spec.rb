# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract::AppliedInvoiceCustomSection do
  subject(:applied_invoice_custom_section) { build(:contract_applied_invoice_custom_section) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:contract) }
  it { is_expected.to belong_to(:invoice_custom_section) }
end
