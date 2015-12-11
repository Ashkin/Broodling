# Name: Patches
# File: patches.rb
# Auth: Terra
# Desc: code-saving utility functions

require 'pp'



# Add Array's #sample (and variants) to hashes
class Hash
  def sample_key;    self.keys[ rand(self.size) ];  end
  def sample_value;  self[ self.sample_key ];       end
  def sample
    key = self.sample_key
    { key => self[key] }
  end
end

# Array#uniq? - Does an array contain only unique elements?
class Array
  def uniq?
    self.uniq == self
  end
end


# Try using rescue when defining a hash?


# Time segments (converted to seconds)
# Ex: 5.weeks,  1.1.minutes
class Numeric
  def seconds;   self;                  end;  alias_method :second,   :seconds
  def minutes;   self         *  60;    end;  alias_method :minute,   :minutes
  def hours;     self.minutes *  60;    end;  alias_method :hour,     :hours
  def days;      self.hours   *  24;    end;  alias_method :day,      :days
  def weeks;     self.days    *   7;    end;  alias_method :week,     :weeks
  def months;    self.years   /  12.0;  end;  alias_method :month,    :months
  def years;     self.days    * 365.25; end;  alias_method :year,     :years
  def decades;   self.years   * 10;     end;  alias_method :decade,   :decades
  def centuries; self.years   * 100;    end;  alias_method :century,  :centuries
end



# Object.is_an? Array
# @mode.in [:playing, :standing]
# var.in Object
# true if var == object
# true if var is inside enumerable (matching any element, sub element, key, value, or within a contained range)
# Does NOT check within strings.   (intended)
class Object
  alias_method :is_an?, :is_a?

  def pp_s
    pps = StringIO.new
    PP.pp(self, pps)
    pps.string
  end

  def in(obj)
    if obj.kind_of? Enumerable  and not obj.is_a? String  # "a" is enumerable; and so would loop infinitely.
      # Can match the entire array/hash, too!
      return true if self == obj
      result = false
      obj.each { |o|
        result = (result or self.in(o))
      }
      return result
    end
    # Match a range itself, or test if it's within the range.
    return (obj.include?(self)  or  (self == o))   if obj.is_a? Range

    self == obj
  end
end




class String
  Colors = { black: 30, red: 31, green: 32, brown: 33, blue: 34, magenta: 35, cyan: 36, gray: 37 }
  Styles = { bold: [1, 22], blink: [5,25] }

  def colorize(color)
    "\033[#{Colors[color.to_sym]}m#{self}\033[0m"
  end

  def stylize(style)
    "\033[#{Styles[style.to_sym][0]}m#{self}\033[#{Styles[style.to_sym][0]}m"
  end

  def method_missing(method, *args, &block)
    if method.to_s.in %w[ black red green brown blue magenta cyan gray bold ]
      self.colorize(method)
    elsif method.to_s.in %w[ bold blink ]
      self.stylize(method)
    else
      super
    end
  end
end
