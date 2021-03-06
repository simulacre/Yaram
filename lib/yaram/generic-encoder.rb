
begin
  require "ox"
rescue LoadError => e
  # we'll use Marshal instead
end # begin


module Yaram
  module GenericEncoder
    class << self
      include Encoder

      if (((oxgem = Gem.loaded_specs["ox"]).is_a?(Gem::Specification)) && Gem::Requirement.new("~>1.2.7").satisfied_by?(oxgem.version))
        include Ox
        
        # Load an object that was dumped using Ox.
        # @raise EncodingError if the expected URN prefix is not found.
        # @param [String] m
        def load(xml)
          header,body = xml[0..11], xml[12..-1]
          raise EncodingError.new(header) unless header == "yaram:ox:   "
          begin
            super(body, :mode => :object)
          rescue Exception => e
            raise ParseError, "unable to parse '#{body}'"
          end # begin
        end # load(xml)
        
        # Dump an object using Ox and prefix it with a URN.
        # @param [Object] o
        # @todo add the Ox version requirement to the prefix URN if the Ox format changes.
        def dump(o)
          "yaram:ox:   " + super(o)
        end # dump(o)
      else
        
        include Marshal
        
        # Load an object that was dumped using Marshal.
        # @raise EncodingError if the expected URN prefix is not found.
        # @param [String] m
        def load(m)
          header,body = m[0..11], m[12..-1]
          raise EncodingError.new(header) unless header == "yaram:mrshl:"
          super(body)
        end
        
        # Dump an object using Marshal and prefix it with a URN.
        # @param [Object] o
        # @todo determine version of Marshal being used and include it in the URN.
        #         str = Marshal.dump("a marshalled message has a major and minor version")
        #         str[0].ord     #=> 4
        #         str[1].ord     #=> 8
        def dump(o)
          "yaram:mrshl:" + super(o)
        end
      end # ((oxgem = Gem.loaded_specs["ox"]).is_a?(Gem::Specification)) && Gem::Requirement.new("~>1.2.2").satisfied_by?(oxgem.version)
    end # << self
    
    
    # insert the generic encoder into the Yaram encoding chain
    inject
    
  end # module::GenericEncoder
end # module::Yaram