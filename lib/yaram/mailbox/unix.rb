require "socket"

module Yaram
  class Mailbox
    class Unix < Mailbox
      include PersistentClients
      
      # @return
      def connect(addr = nil)
        close if bound?
        uri = URI.parse(@address || addr)
        raise ArgumentError.new("address '#{addr}' scheme must be unix").extend(::Yaram::Error) unless uri.scheme == "unix"

        pdir = File.dirname(uri.path)
        Dir.mkdir(pdir) unless File.exists?(pdir)

        @io          = UNIXSocket.new(uri.path).recv_io
        @io.nonblock = true
        @address     = addr
        super()
      end # connect
      
      
      def bind(addr = nil)
        close if connected?
        addr        = (@address || "unix:///tmp/actors/#{Process.pid}-#{UUID.generate}.uds")  if addr.nil?
        @address    = addr
        uri         = URI.parse(addr)
        raise ArgumentError.new("address '#{addr}' scheme must be unix").extend(::Yaram::Error) unless uri.scheme == "unix"
        
        pdir = File.dirname(uri.path)
        Dir.mkdir(pdir) unless File.exists?(pdir)

        @inboxes = []        
        @io      = @socket = UNIXServer.new(uri.path)
        
        super()
        inboxes
        self
      end # bind(bind_ip = nil)
      
      # @return [String] address
      def close
        @inboxes.each{|i| i.close } if @bound
        path = @socket.path
        @socket.close
        File.delete(path)
        @address
      end # close
      

      private
      
      # Check for any clients that have innitaitied a connection 
      # and add their socket connections to the list of inboxes
      # to check.
      # @return [Yaram::Mailbox::Unix] self
      def inboxes
        nomoreclients = false
        until nomoreclients
          begin
            c   = @socket.accept_nonblock
            r,w = IO.pipe
            c.send_io(w)
            @inboxes.push(r)
          rescue IO::WaitReadable, Errno::EINTR
            nomoreclients = true
          end # begin          
        end # nomoreclients
        @inboxes
      end # add_clients
      
      
    end # class::Unix < Mailbox
  end # class::Mailbox
end # module::Yaram
