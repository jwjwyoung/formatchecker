class Concern
  attr_accessor :name, :has_manys, :has_ones, :has_belongs, :belongs_tos

  def initialize(name = "")
    @name = name
    @has_manys = Set.new
    @has_ones = Set.new
    @has_belongs = Set.new
    @belongs_tos = Set.new
  end

  def self.from_ast(ast)
    ret = Concern.new
    parse = lambda do |ast|
      case ast.type
      when :list
        ast.children.each do |child|
          parse.call(child)
        end
      when :module
        name = ast[0].source
        ret.name += name + "::"
        if ast[1] && ast[1].type == :list
          ast[1].each do |child|
            parse.call(child)
          end
        end
      when :fcall
        fname = ast[0].source
        do_block = ast[2]
        if fname == "included" && do_block&.type == :do_block
          inc = parse_included(do_block[1])
          ret.belongs_tos += inc[:belongs_tos]
          ret.has_ones += inc[:has_ones]
          ret.has_manys += inc[:has_manys]
          ret.has_belongs += inc[:has_belongs]
        end
      end
    end

    parse.call(ast)
    ret.name.chomp! "::"
    ret
  end
end

def parse_included(do_block)
  assoc = %i[
    belongs_tos has_ones has_manys has_belongs
  ].each_with_object({}) { |obj, memo| memo[obj] = Set.new }

  do_block.each do |child|
    next if child.type != :command

    fname = child[0].source
    case fname
    when "belongs_to"
      key_field = parse_foreign_key(child[1])
      assoc[:belongs_tos] << key_field if key_field
    when "has_one"
      modname = handle_symbol_literal_node(child[1][0])
      assoc[:has_ones] << modname
    when "has_many"
      modname = handle_symbol_literal_node(child[1][0]).singularize
      assoc[:has_manys] << modname
    when "has_and_belongs_to_many"
      modname = handle_symbol_literal_node(child[1][0]).singularize
      assoc[:has_belongs] << modname
    end
  end
  assoc
end
