# frozen_string_literal: true

module Invoices
  module EmailDelivery
    module_function

    def enabled?
      License.premium? || Emails::PosterService.configured?
    end
  end
end
