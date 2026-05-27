require_relative '../spec_helper'

describe 'TCPServer#shutdown' do
  before do
    @server = TCPServer.new('127.0.0.1', 0)
  end

  after do
    @server.close unless @server.closed?
  end

  it 'shuts down the listener' do
    @server.shutdown.should == 0
  end
end
