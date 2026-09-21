# frozen_string_literal: true

module Invoices
  module EmailDelivery
    module_function

    def enabled?
      Emails::PosterService.enabled? || License.premium?
    end
  end
end
