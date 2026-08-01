# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks for empty strings in the `arch` stanza.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # arch arm: "-arm64", intel: ""
      #
      # # good
      # arch arm: "-arm64"
      # ```
      class EmptyArchArgument < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Remove the empty `%<key>s:` argument from the `arch` stanza."
        MSG_STANZA = "Remove the `arch` stanza as all its arguments are empty."

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if node.method_name != :arch || node.receiver
          return unless (hash = node.first_argument)&.hash_type?

          pairs = hash.pairs
          return if pairs.none? { |pair| empty_string_value?(pair) }

          if pairs.all? { |pair| empty_string_value?(pair) }
            add_offense(node, message: MSG_STANZA) do |corrector|
              corrector.remove(range_by_whole_lines(node.source_range, include_final_newline: true))
            end
            return
          end

          pairs.each_with_index do |pair, index|
            next unless empty_string_value?(pair)

            key = (pair.key.sym_type? || pair.key.str_type?) ? pair.key.value : pair.key.source

            add_offense(pair, message: format(MSG, key:)) do |corrector|
              range = if index.zero?
                pair.source_range.join(pairs.fetch(1).source_range.begin)
              else
                pairs.fetch(index - 1).source_range.end.join(pair.source_range.end)
              end
              corrector.remove(range)
            end
          end
        end

        private

        sig { params(pair: RuboCop::AST::PairNode).returns(T::Boolean) }
        def empty_string_value?(pair)
          pair.value.str_type? && pair.value.value.empty?
        end
      end
    end
  end
end
