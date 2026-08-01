# typed: strict
# frozen_string_literal: true

class Hash
  # Returns a deep copy of hash.
  #
  #   hash = { a: { b: 'b' } }
  #   dup  = hash.deep_dup
  #   dup[:a][:c] = 'c'
  #
  #   hash[:a][:c] # => nil
  #   dup[:a][:c]  # => "c"
  sig { returns(T.self_type) }
  def deep_dup
    hash = dup
    each_pair do |key, value|
      case key
      when ::String, ::Symbol
        hash[key] = T.unsafe(value).deep_dup
      else
        hash.delete(key)
        hash[T.unsafe(key).deep_dup] = T.unsafe(value).deep_dup
      end
    end
    hash
  end
end
