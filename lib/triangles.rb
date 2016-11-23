require "triangles/version"

Equilateral = 1
Isosceles = 2
Scalene = 3

# The run method is used only by the console to display 'human' results:
def run(s1, s2, s3)
  ["Equilateral", "Isosceles", "Scalene"][triangle_kind(s1, s2, s3) - 1]
end

# The triangle_kind return the proper value as the constants above
# using one of four methods.
# The input here is 3 seperated values - for a triangle.
# The other function get an array, since they can be used in general
# with bigger arrays.
# uncomment the method you want to use.
def triangle_kind(s1, s2, s3)
  raise ArgumentError if [s1, s2, s3].any? { |n| n <= 0 }

  # kind_for_machine_code([s1, s2, s3])
  # kind_using_hash([s1, s2, s3])
  # kind_using_repetitions_hash([s1, s2, s3])
  kind_using_set([s1, s2, s3])
end

# This method is the less general method - it cannot fit to other
# problems. However, if we have to categorize 1 milion of triangles
# using a true compiler - this generates the smallest and fastest
# machine code.
def kind_for_machine_code(array)
  s1, s2, s3 = array
  if s1 == s2
    s1 == s3 ? Equilateral : Isosceles
  else
    if s1 == s3
      Isosceles
    else
      s2 == s3 ? Isosceles : Scalene
    end
  end
end

# The problem we have represent a general problem of finding repetitions
# of values in an array.
# We can use hash, by using the input values as keys, and group them to
# arrays contining these keys. for example"
# [1,3,3] => { 1: [1], 3: [3,3] }
# Counting the keys give us the result.
def kind_using_hash(array)
  array.group_by(&:itself).count
end

# For mor general problems we want to know how many repetitions each value
# have in the input array.
# The following function return a hash like this:
# [1,3,3] => {1: 1, 3: 2}
def repetitions(array)
  array.each_with_object(Hash.new(0)) { |s, hash| hash[s] += 1 }
end

# we can use the repetitions hash also in our problem.
# This function is lighter in resources then the former hash:
def kind_using_repetitions_hash(array)
  repetitions(array).count
end

# We can use set to check how many different values we have.
# for example - [1,3,3] will give us (1,3) and the count - 2
# is the result.
# This is the simplest method for triangles, and can be used for other
# problems as well, but it is less generic then a hash.
def kind_using_set(array)
  array.to_set.count
end
