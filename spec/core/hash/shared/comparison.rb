describe :hash_comparison, shared: true do
  it "raises a TypeError if the right operand is not a hash" do
    -> { { a: 1 }.send(@method, 1) }.should raise_error(TypeError)
    -> { { a: 1 }.send(@method, nil) }.should raise_error(TypeError)
    -> { { a: 1 }.send(@method, []) }.should raise_error(TypeError)
  end

  it "preserves the class returned by to_hash in the error" do
    obj = Object.new
    def obj.to_hash
      nil
    end

    -> { { a: 1 }.send(@method, obj) }.should raise_error(
      TypeError,
      "can't convert Object to Hash (Object#to_hash gives NilClass)"
    )
  end

  it "returns false if both hashes have the same keys but different values" do
    h1 = { a: 1 }
    h2 = { a: 2 }

    h1.send(@method, h2).should be_false
    h2.send(@method, h1).should be_false
  end
end
