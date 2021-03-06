require File.join(File.dirname(__FILE__), "spec_helper")

describe Yaram do
  it "should work with the default type of mailbox" do
    actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false))
    actor.sync(:status).should == :up
  end # it should work with memory mailboxs
  
  describe "udp mailbox" do
    it "should work with udp mailboxs" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Udp))
      actor.sync(:status).should == :up
    end # it should work with udp mailboxs      
    it "should provide an address for external actors" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Udp))
      actor.address.should include("udp")
      actor.sync(:address).should_not be actor.address
    end # it should provide an address for external actors
    
    it "should allow the caller to define the address of the actor" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => "udp://127.0.0.1:5897"))
      actor.outbox.address.should == "udp://127.0.0.1:5897"
      actor.sync(:status).should == :up
    end # it should allow the caller to define the address of the actor  

    it "should not duplicate ports for active actors" do
      a1 = Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Udp)
      a2 = Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Udp)
      URI.parse(a1).port.should_not == URI.parse(a2).port
    end # it should not duplicate ports for active actors  

    it "should be fast" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:mailbox => Yaram::Mailbox::Udp, :log => false))
      actor.!(:inc, 1) # initial connection setup takes about 0.03 seconds
      expect {
        100000.times { actor.!(:inc, 1) } 
      }.to take_less_than(1).seconds
    end # it should be fast
  end # "udp mailboxs"

  describe "tcp mailboxes" do
    it "should work with tcp mailboxes" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Tcp))
      actor.sync(:status).should == :up
    end # it should work with tcp mailboxs
    
    it "should not duplicate ports for active actors" do
      a1 = Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Tcp)
      a2 = Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Tcp)
      URI.parse(a1).port.should_not == URI.parse(a2).port
    end # it should not duplicate ports for active actors  
    
    it "should be fast" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:mailbox => Yaram::Mailbox::Tcp, :log => false))
      actor.!(:inc, 1) # initial connection setup takes about 0.03 seconds
      expect {
        100000.times { actor.!(:inc, 1) } 
      }.to take_less_than(1).seconds
    end # it should be fast  
  end # "tcp mailboxes"
  
  describe "fifo mailbox" do
    it "should work with fifo mailboxs" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Fifo))
      actor.sync(:status).should == :up
    end # it should work with fifo mailboxs    
  end # "fifo mailbox"

  describe "unix domain socket mailbox" do
    it "should work with domain sockets" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:mailbox => Yaram::Mailbox::Unix, :log => false))
      actor.sync(:status).should == :up      
    end # it should work with domain sockets
    pending{
      it "should support multiple client connections" do
        addr = Yaram::Test::MCounter.new.spawn(:mailbox => Yaram::Mailbox::Unix, :log => false)
        c0 = Yaram::Actor::Proxy.new(addr)
        c1 = Yaram::Actor::Proxy.new(addr)
        c2 = Yaram::Actor::Proxy.new(addr)
        c1.!(:inc, 1)
        c0.sync(:status).should == :up
        c2.!(:inc, 3)
        c1.!(:inc, 3)
        c2.sync(:status).should == :up
        c1.sync(:status).should == :up
        c0.sync(:status).should == :up
        c0.sync(:value).should == 7
      end # it should support multiple client connections
    }
    it "should be fast" do
      actor = Yaram::Actor::Proxy.new(Yaram::Test::MCounter.new.spawn(:mailbox => Yaram::Mailbox::Unix, :log => false))
      actor.!(:inc, 1) # initial connection setup takes about 0.03 seconds
      sleep 1
      expect {
        100000.times { actor.!(:inc, 1) } 
      }.to take_less_than(1).seconds
    end # it should be fast
  end # "unix domain socket mailbox"
  
  describe "redis mailbox" do
    it "should work with redis mailboxes" do
      pending("no redis server at 127.0.0.1") unless Yaram::Test.redis_up?("127.0.0.1")
      actor = Yaram::Actor::Proxy.new(
                Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Redis.new("redis://127.0.0.1/#{UUID.generate}"))
              )
      actor.sync(:status).should == :up
    end # it should work with redis mailboxs
    
    it "should be reliable", :slow => true do
      pending("no redis server at 127.0.0.1") unless Yaram::Test.redis_up?("127.0.0.1")
      actor = Yaram::Actor::Proxy.new(
                Yaram::Test::MCounter.new.spawn(:log => true, :mailbox => Yaram::Mailbox::Redis.new("redis://127.0.0.1/#{UUID.generate}"))
              )
      actor.!(:inc, 1) # initial connection setup takes about 0.03 seconds
      sleep 1
      25000.times { actor.!(:inc, 1) }
      actor.request([:value], :timeout => 50).should == 25001
    end # should be reliable
    
    it "should be fast" do
      pending("no redis server at 127.0.0.1") unless Yaram::Test.redis_up?("127.0.0.1")
      actor = Yaram::Actor::Proxy.new(
                Yaram::Test::MCounter.new.spawn(:log => false, :mailbox => Yaram::Mailbox::Redis.new("redis://127.0.0.1/#{UUID.generate}"))
              )
      actor.!(:inc, 1) # initial connection setup takes about 0.03 seconds
      expect {
        100000.times { actor.!(:inc, 1) } 
      }.to take_less_than(3).seconds
    end # it should be fast
  end # "redis mailbox"
end # describe Yaram