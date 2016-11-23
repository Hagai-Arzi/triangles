require 'spec_helper'

describe "triangle_kind" do
  it 'returns Equilateral for [3,3,3]' do
    expect(triangle_kind(3,3,3)).to be Equilateral
  end

  it 'returns Isosceles for [3,2,3]' do
    expect(triangle_kind(3,2,3)).to be Isosceles
  end

  it 'returns Scalene for [1,2,3]' do
    expect(triangle_kind(1,2,3)).to be Scalene
  end

  it "raise an exception for zero input" do
    expect { triangle_kind(3,3,0) }.to raise_error(ArgumentError)
  end

  it "raise an exception for negative input" do
    expect{ triangle_kind(3,-4,3) }.to raise_error(ArgumentError)
  end
end
