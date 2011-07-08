module Yaram
  # @todo Add an #rpc and #rpc_noblock method
  # @todo setup the supervisor to restart the actor if it crashes
  # @todo trap Ctrl-C and stop actor
  module Actor

    # Send a message asynchronously
    def !(meth, *args)
      publish([meth, *args])
    end 
    
    # Send a message and wait for a reply
    def sync(meth, *args)
      request([meth, *args])
    end
    
    # If a request results in the actor restarting then resend the last request.
    # This is currently not correct behavior because the msg that caused the actor
    # to crash was msg N-1 not N. We will loose one message instead of two, but we
    # want to loose zero.
    # @return
    def recover(times = 1)
      begin
        yield
      rescue Yaram::ActorRestarted => e
        times -= 1
        times > -1 ? retry : raise(e)
      end # begin
    end # retry(times = 1)
    
    # Stop the actor and start it again.
    # The actor's current message queue will be written to a log file.
    # @return
    def restart
      stop
      @tpid, @in, @out = Yaram::Actor.start(@actorklass)
    end # restart
    
    def stop
      begin
        Process.getpgid(@tpid)
        Process.kill(:TERM, @tpid)
      rescue Errno::ESRCH => e
      end # begin
    end # close
    
    class << self
      # Start an instance of Class that includes Yaram::Actor, or inherits from Yaram::Actor::Base
      def start(klass, opts = {})
        opts = {:log => nil, :pipe => IO }.merge(opts.is_a?(Hash) ? opts : {})
        
        child_read, parent_write = opts[:pipe].pipe # IO.pipe
        parent_read, child_write = opts[:pipe].pipe # IO.pipe
        [child_write, child_read, parent_read, parent_write].each do |io|
          if defined? Fcntl::F_GETFL
            io.fcntl(Fcntl::F_SETFL, io.fcntl(Fcntl::F_GETFL) | Fcntl::O_NONBLOCK)
          else
            io.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
          end # defined? Fcntl::F_GETFL
        end # do  |io|
        
        pid = Process.fork do
          at_exit { puts "#{$0} terminating" }
          begin
            parent_write.close
            parent_read.close
            $0      = "yaram_#{klass.to_s.downcase.split("::")[-1]}"
            
            if opts[:log] == false
              STDOUT.reopen "/dev/null"
              STDERR.reopen "/dev/null"
            elsif opts[:log].is_a?(String)
              STDOUT.reopen opts[:log] + "stdout"
              STDERR.reopen opts[:log] + "stderr"
            else
              ts      = Time.new.to_i
              STDOUT.reopen "#{$0}.#{ts}.#{Process.pid}.stdout"
              STDERR.reopen "#{$0}.#{ts}.#{Process.pid}.stderr"
            end # opts[:log] == false
            
            klass.new.send(:subscribe, child_read, child_write)
          ensure
            child_read.close
            child_write.close
          end # begin
          Process.exit
        end # Process.fork
        
        raise StartError, "unable to fork actor" if pid == -1
        
        child_read.close
        child_write.close
        
        at_exit do
          begin
            Process.getpgid(pid)
            Process.kill(:TERM, pid) 
          rescue Errno::ESRCH => e
          end # begin
        end # at_exit

        #puts "#{klass} is running in process #{pid}"
        [pid, parent_read, parent_write]
      end # start
    end # class::self

    
    
    private

    # Prepare an Actor for work.
    # @lock will be created for thread synchronization.
    #
    # When called by the process that is creating an actor a Class must be passed in.
    # @tpid, @in, and @out will be created
    #
    # When called by the process that will be the actor, no klass can be provided.
    #
    # @return
    def prepare(klass = nil, opts = {})
      @lock = Mutex.new
      
      if klass.nil?
        # We are the actor process
        @tpid = Process.ppid
        return self
      end # klass.nil?
      
      raise ArgumentError, "klass '#{klass}' must be an instantiatable class" unless klass.is_a?(Class)
      @actorklass      = klass
      @tpid, @in, @out = Yaram::Actor.start(@actorklass, opts)
      @tpid
    end # prepare
    
    # Publish a message and don't wait for a response.
    # Is not thread-safe; you need to synchronize with the lock before calling.
    # @param [Object] msg the thing to publish
    # @todo raise an execption if @out is closed on tracker process is down
    def publish(msg)
      begin
        @out.write("#{Ox.dump(msg)}]]>]]>")
      rescue Errno::EPIPE => e
        @tpid, @in, @out = Yaram::Actor.start(@actorklass)
        raise ActorRestarted, "#{@actorklass} process was automatically restarted; resend message(s) manually"
      end # begin
    end # publish(*msg)
    alias :reply :publish
    
    # Retrieve a message.
    # Is not thread-safe; you need to synchronize with the lock before calling.
    # @return
    def get(timeout = 1)
      begin
        return if IO.select([@in], nil, nil, timeout).nil?
        msgs = ""
        true while ((msgs += @in.readpartial(4096))[-6..-1] != "]]>]]>")
        # @todo apply context ids to messages - pull off the reply with the same context id and
        #       leave the rest for now, just assume that the last message is the one we want.
        Ox.load(msgs.split("]]>]]>").pop, :mode => :object)
      rescue EncodingError => e
        raise e.extend(::Yaram::Error)#.add_data(msgs)
      rescue Exception => e
        raise e.extend(::Yaram::Error)
      end # begin
    end # get_msg
    
    # Send a message and wait for a response
    # Sychrnozises with the lock, so it's thread-safe.
    # @return [Object] the response to the message
    #
    # @todo ensure that the reply is for the request: context ids?
    # there is nothing preventing the actor from publishing unsollicited events
    def request(msg, timeout = 1)
      @lock.synchronize do
        publish(msg)
        get(timeout)
      end # synchronize do 
    end # send(msg, timeout = 1)

    # Subscribe to an input stream.
    # If a block is provided all decoded messages will be passed to it. Otherwise 
    # a local method will be called based on the message received.
    # @param [IO] input the source of messages
    # @param [IO] output where to send any replies
    # Does not return
    def subscribe(input, output)
      @out = output
      @in  = input
      
      loop do
        msgs = ""
        begin
          IO.select([input], nil, nil, 0)
          true while (msgs += input.readpartial(4096))[-6 .. -1] != "]]>]]>"
          msgs = msgs.split("]]>]]>")
          while (msg = msgs.shift) do
            begin
              if block_given?
                yield(Ox.load(msg, :mode => :object))
              else
                meth, *args = Ox.load(msg, :mode => :object)
                unless (meth.is_a?(String) && !meth.empty?) || meth.is_a?(Symbol)
                  #raise ArgumentError.new("'#{meth.inspect}' must be a String or Symobl")
                  reply(ArgumentError.new"'#{meth.inspect}' must be a String or Symobl")
                  next
                end
                send(meth, *args)
              end # block_given?
            rescue Exception => e
              puts "=-=-=-=-=-=-= processing failure =-=-=-=-=-=-=\nfailed for message:\n#{msg}"
              raise e
            end # begin
          end # do  |msg|
          
        rescue Exception => e
          puts "=-=-=-=-=-=-= message queue =-=-=-=-=-=-=\n#{msgs.is_a?(Array) ? msgs.join("\n") : msgs}\n=-=-=-=-=-=-= message queue end =-=-=-=-=-=-="
          raise e.extend(::Yaram::Error)
        end # begin
      end # loop do
    end # subscribe(io)
    
    
    # Confirms that the other side is up and capable of communication.
    # @return
    def require_channel
      begin
        Process.getpgid(@tpid)
      rescue Errno::ESRCH => e
        # no such process
        raise e.extend(::Yaram::Error)
      end # begin
    end # require_channel
    
    
    
    public
    
    # Allows for inheritence of Yaram::Actor
    class Base
      include Actor 
      def initialize
        prepare
      end # initialize
    end # class::Base
    
    class Simple < Base
      def initialize(klass = nil, opts = {})
        prepare(klass, opts)
      end 
      
      def method_missing(meth, *args)
        self.!(meth, *args)
      end 
    end # class::Simple < Base
  end # module::Actor
end # module::Yaram