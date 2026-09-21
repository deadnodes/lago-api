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

    def perform(invoice:, to: nil, cc: nil, bcc: nil)
      if Emails::PosterService.configured?
        Emails::PosterService.call!(invoice:, to:, cc:, bcc:)
      else
        params = {invoice:}
        params[:to] = to if to
        params[:cc] = cc if cc
        params[:bcc] = bcc if bcc
        InvoiceMailer.with(params).created.deliver_later
      end
    end
  end
end
