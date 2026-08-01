# typed: strict
# frozen_string_literal: true

class Array
  # Returns a deep copy of array.
  #
  #   array = [1, [2, 3]]
  #   dup   = array.deep_dup
  #   dup[1][2] = 4
  #
  #   array[1][2] # => nil
  #   dup[1][2]   # => 4
  sig { returns(T.self_type) }
  def deep_dup
    T.unsafe(self).map(&:deep_dup)
  end
end
