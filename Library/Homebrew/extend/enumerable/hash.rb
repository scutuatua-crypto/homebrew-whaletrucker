# typed: strict
# frozen_string_literal: true

class Hash
  # {Hash#reject} has its own definition, so this needs one too.
  def compact_blank = reject { |_k, v| T.unsafe(v).blank? }
end
