# Name: Patches
# File: patches-selenium.rb
# Auth: Terra
# Desc: code-saving utility functions for Selenium-webdriver

require 'selenium-webdriver'



## driver.Ele()
# Shorthand for driver.find_element()
# Also supports simple, CSS-like selectors  (ex: name#id.class1.class2)
class Selenium::WebDriver::Driver
  def ele(selector)
    return find_element(convert_selector(selector))
  end

  def eles(selector)
    return find_elements(convert_selector(selector))
  end

  def ele_exists?(selector)
    eles(selector).size()>0
  end

  # Complete element usability check
  def ele_available?(selector)
    return nil if not ele_exists?(selector) # Hack
    ele_exists?(selector) and ele_enabled?(selector) and ele_visible?(selector) and ele_displayed?(selector)
  rescue
    return nil # Hack
  end

  def ele_visible?(selector)
    return nil if not ele_exists?(selector) # Hack
    element = ele(selector)
    element.style("visibility") != "hidden"  or  element.style("opacity").to_s != "0"
  end

  def ele_enabled?(selector)
    return nil if not ele_exists?(selector) # Hack
    not ele_disabled?(selector)
  end
  def ele_disabled?(selector)
    return nil if not ele_exists?(selector) # Hack
    element = ele(selector)
    element.attribute("disabled")  or element.attribute("class").include? "disabled"
  end

  def ele_displayed?(selector)
    return nil if not ele_exists?(selector) # Hack
    ele(selector).displayed?
  end

end


# internal method -- allows use of css-like selectors (ex: name#id.class1.class2)
def convert_selector(selector)
  if (!selector.is_a? String)
    self.quit
    raise ArgumentError, "fatal: convert_selector() expected String, got #{selector.class}\n" +
                         "(#{__FILE__}:#{__LINE__})"
  end
  # split into name, #id, .classes
  matches = /([a-zA-Z0-9_\-\[\]]*)?(#[a-zA-Z0-9_\-\[\]]*)?(\.[a-zA-Z0-9_\-\[\]\.]*)?/.match(selector)
  return printf("No match (#{selector} ~> nil)\n") if matches.nil?
  pieces = {}
  pieces[:name]  = matches[1]
  pieces[:id]    = matches[2][1..-1]                 if matches[2]  # Remove the leading # marker
  pieces[:class] = matches[3][1..-1].gsub("\."," ")  if matches[3]  # ".class1.class2" => "class1 class2"
  pieces.delete_if{|k,v| v.to_s.empty?} # strip nil's as find_element() is silly and doesn't ignore them.
  pieces
end



# Shorthand for Selenium WebDriver's Wait:
# Wait.upto(5.days).for {condition}
module Wait
  def self.upto duration
    raise ArgumentError, "Invalid duration specified" if not duration.kind_of? Numeric
    Selenium::WebDriver::Wait.new(:timeout => duration)
  end
end

# Alias: Wait.for
class Selenium::WebDriver::Wait
  alias_method :for, :until
end
