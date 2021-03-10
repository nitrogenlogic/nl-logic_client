# NL::LogicClient

This is the Ruby client for the Nitrogen Logic [Automation Controller][1].
It's used internally by the Automation Controller's web browser-based interface
to connect to the automation logic system.

# Copying

&copy;2011-2021 Mike Bourgeous.  Released under [AGPLv3][0].

Use in new projects is not recommended.

# Usage

Add this line to your application's Gemfile:

```ruby
gem 'nl-logic_client'
```

See `bin/set_multi.rb`, `bin/list_exports.rb`, and `bin/show_info.rb` for usage
examples.  Additional practical examples will eventually be available when the
Sinatra-based Automation Controller web server is released.

[0]: https://www.gnu.org/licenses/agpl-3.0.html
[1]: http://www.nitrogenlogic.com/products/automation_controller.html
