# frozen_string_literal: true

module Invoices
  class NotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :invoices
      end
    end

    def perform(invoice:)
      if Emails::PosterService.enabled?
        Emails::PosterService.call!(invoice:)
      else
        InvoiceMailer.with(invoice:).finalized.deliver_later
      end
    end
  end
end
