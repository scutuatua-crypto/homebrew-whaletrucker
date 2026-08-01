# typed: strict
# frozen_string_literal: true

class String
  BLANK_RE = /\A[[:space:]]*\z/
  # This is a cache that is intentionally mutable
  # rubocop:disable Style/MutableConstant
  ENCODED_BLANKS_ = T.let(Hash.new do |h, enc|
    h[enc] = Regexp.new(BLANK_RE.source.encode(enc), BLANK_RE.options | Regexp::FIXEDENCODING)
  end, T::Hash[Encoding, Regexp])
  # rubocop:enable Style/MutableConstant

  # A string is blank if it's empty or contains whitespaces only:
  #
  # ```ruby
  # ''.blank?       # => true
  # '   '.blank?    # => true
  # "\t\n\r".blank? # => true
  # ' blah '.blank? # => false
  # ```
  #
  # Unicode whitespace is supported:
  #
  # ```ruby
  # "\u00a0".blank? # => true
  # ```
  sig { returns(T::Boolean) }
  def blank?
    # The regexp that matches blank strings is expensive. For the case of empty
    # strings we can speed up this method (~3.5x) with an empty? call. The
    # penalty for the rest of strings is marginal.
    empty? ||
      begin
        BLANK_RE.match?(self)
      rescue Encoding::CompatibilityError
        T.must(ENCODED_BLANKS_[encoding]).match?(self)
      end
  end

  sig { returns(T::Boolean) }
  def present? = !blank? # :nodoc:
end
