require_relative '../../spec_helper'

describe "Hash#any?" do
  describe 'with no block given' do
    it "checks if there are any members of a Hash" do
      empty_hash = {}
      expect(empty_hash.any?).to equal(false)

      hash_with_members = { 'key' => 'value' }
      expect(hash_with_members.any?).to equal(true)
    end
  end

  describe 'with a block given' do
    it 'is false if the hash is empty' do
      empty_hash = {}
      expect(empty_hash.any? {|k,v| 1 == 1 }).to equal(false)
    end

    it 'is true if the block returns true for any member of the hash' do
      hash_with_members = { 'a' => false, 'b' => false, 'c' => true, 'd' => false }
      expect(hash_with_members.any? {|k,v| v == true}).to equal(true)
    end

    it 'is false if the block returns false for all members of the hash' do
      hash_with_members = { 'a' => false, 'b' => false, 'c' => true, 'd' => false }
      expect(hash_with_members.any? {|k,v| v == 42}).to equal(false)
    end
  end
end