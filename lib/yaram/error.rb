module Yaram
  # A Yaram::Actor error tag that will be applied to Exceptions caught internally
  module Error; end
  
  # The standard error class that all Yaram::Actor errors inherit from. 
  # It also applies the Yaram::Error tag to inheritors
  class StandardError < ::StandardError
    def initialize(*args)
      super(*args)
      extend Error
    end # initialize(*args)
  end # StandardError < ::StandardError
  
  # The process running the Actor instance did not properly start
  class StartError < StandardError; end
  
  # Failed to send the message probably because the actor died. The 
  # supervisor process will restart it automatically, but the caller
  # must resend manually.
  class ActorRestarted < StandardError; end

  # The actor died.
  class ActorDied < StandardError; end
  
  class CommunicationError < StandardError; end
  
  # A message that was receive from a third-party broker could not be 
  # properly parsed.
  class ParseError < StandardError; end
  
  class EncodingError < StandardError; end
end # module::Yaram