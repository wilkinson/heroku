require "vendor/heroku/okjson"

module Heroku
  module Helpers
    def home_directory
      running_on_windows? ? ENV['USERPROFILE'].gsub("\\","/") : ENV['HOME']
    end

    def running_on_windows?
      RUBY_PLATFORM =~ /mswin32|mingw32/
    end

    def running_on_a_mac?
      RUBY_PLATFORM =~ /-darwin\d/
    end

    def display(msg="", new_line=true)
      if new_line
        puts(msg)
      else
        print(msg)
        $stdout.flush
      end
    end

    def redisplay(line, line_break = false)
      display("\r\e[0K#{line}", line_break)
    end

    def deprecate(message)
      display "WARNING: #{message}"
    end

    def error(msg)
      $stderr.puts(format_with_bang(msg))
      exit(1)
    end

    def confirm_billing
      display
      display "This action will cause your account to be billed at the end of the month"
      display "For more information, see http://devcenter.heroku.com/articles/billing"
      display "Are you sure you want to do this? (y/n) ", false
      if ask.downcase == 'y'
        heroku.confirm_billing
        return true
      end
    end

    def confirm(message="Are you sure you wish to continue? (y/n)?")
      display("#{message} ", false)
      ask.downcase == 'y'
    end

    def confirm_command(app_to_confirm = app, message=nil)
      raise(Heroku::Command::CommandFailed, "No app specified.\nRun this command from app folder or set it adding --app <app name>") unless app_to_confirm

      if respond_to?(:extract_option) && confirmed_app = extract_option('--confirm', false)
        unless confirmed_app == app_to_confirm
          raise(Heroku::Command::CommandFailed, "Confirmed app #{confirmed_app} did not match the selected app #{app_to_confirm}.")
        end
        return true
      else
        display
        message ||= "WARNING: Potentially Destructive Action\nThis command will affect the app: #{app_to_confirm}"
        message << "\nTo proceed, type \"#{app_to_confirm}\" or re-run this command with --confirm #{app_to_confirm}"
        output_with_bang(message)
        display
        display "> ", false
        if ask.downcase != app_to_confirm
          output_with_bang "Input did not match #{app_to_confirm}. Aborted."
          false
        else
          true
        end
      end
    end

    def format_date(date)
      date = Time.parse(date) if date.is_a?(String)
      date.strftime("%Y-%m-%d %H:%M %Z")
    end

    def ask
      STDIN.gets.strip
    end

    def shell(cmd)
      FileUtils.cd(Dir.pwd) {|d| return `#{cmd}`}
    end

    def run_command(command, args=[])
      Heroku::Command.run(command, args)
    end

    def retry_on_exception(*exceptions)
      retry_count = 0
      begin
        yield
      rescue *exceptions => ex
        raise ex if retry_count >= 3
        sleep 3
        retry_count += 1
        retry
      end
    end

    def has_git?
      %x{ git --version }
      $?.success?
    end

    def git(args)
      return "" unless has_git?
      flattened_args = [args].flatten.compact.join(" ")
      %x{ git #{flattened_args} 2>&1 }.strip
    end

    def time_ago(elapsed)
      if elapsed <= 60
        "#{elapsed.floor}s ago"
      elsif elapsed <= (60 * 60)
        "#{(elapsed / 60).floor}m ago"
      elsif elapsed <= (60 * 60 * 24)
        "#{(elapsed / 60 / 60).floor}h ago"
      else
        (Time.now - elapsed).strftime("%Y-%m-%d %H:%M:%S")
      end
    end

    def truncate(text, length)
      if text.size > length
        text[0, length - 2] + '..'
      else
        text
      end
    end

    @@kb = 1024
    @@mb = 1024 * @@kb
    @@gb = 1024 * @@mb
    def format_bytes(amount)
      amount = amount.to_i
      return '(empty)' if amount == 0
      return amount if amount < @@kb
      return "#{(amount / @@kb).round}k" if amount < @@mb
      return "#{(amount / @@mb).round}M" if amount < @@gb
      return "#{(amount / @@gb).round}G"
    end

    def quantify(string, num)
      "%d %s" % [ num, num.to_i == 1 ? string : "#{string}s" ]
    end

    def create_git_remote(remote, url)
      return if git('remote').split("\n").include?(remote)
      return unless File.exists?(".git")
      git "remote add #{remote} #{url}"
      display "Git remote #{remote} added"
    end

    def longest(items)
      items.map { |i| i.to_s.length }.sort.last
    end

    def display_table(objects, columns, headers)
      lengths = []
      columns.each_with_index do |column, index|
        header = headers[index]
        lengths << longest([header].concat(objects.map { |o| o[column].to_s }))
      end
      lines = lengths.map {|length| "-" * length}
      lengths[-1] = 0 # remove padding from last column
      display_row headers, lengths
      display_row lines, lengths
      objects.each do |row|
        display_row columns.map { |column| row[column] }, lengths
      end
    end

    def display_row(row, lengths)
      row_data = []
      row.zip(lengths).each do |column, length|
        format = column.is_a?(Fixnum) ? "%#{length}s" : "%-#{length}s"
        row_data << format % column
      end
      display(row_data.join("  "))
    end

    def json_encode(object)
      Heroku::OkJson.encode(object)
    rescue Heroku::OkJson::Error
      nil
    end

    def json_decode(json)
      Heroku::OkJson.decode(json)
    rescue Heroku::OkJson::Error
      nil
    end

    def set_buffer(enable)
      with_tty do
        if enable
          `stty icanon echo`
        else
          `stty -icanon -echo`
        end
      end
    end

    def with_tty(&block)
      return unless $stdin.isatty
      begin
        yield
      rescue
        # fails on windows
      end
    end

    def get_terminal_environment
      { "TERM" => ENV["TERM"], "COLUMNS" => `tput cols`, "LINES" => `tput lines` }
    rescue
      { "TERM" => ENV["TERM"] }
    end

    def fail(message)
      raise Heroku::Command::CommandFailed, message
    end

    ## DISPLAY HELPERS

    def action(message, options={})
      display("#{message}... ", false)
      Heroku::Helpers.enable_error_capture
      ret = yield
      display((options[:success] || "done"), false)
      display(", #{@status}", false) if @status
      display
      ret
    ensure
      Heroku::Helpers.disable_error_capture
    end

    def status(message)
      @status = message
    end

    def format_with_bang(message)
      return '' if message.to_s.strip == ""
      " !    " + message.split("\n").join("\n !    ")
    end

    def output_with_bang(message="", new_line=true)
      return if message.to_s.strip == ""
      display(format_with_bang(message), new_line)
    end

    def error_with_failure(message)
      display "failed"
      $stderr.puts(format_with_bang(message))
      exit(1)
    end

    def self.included_into
      @@included_into ||= []
    end

    def self.extended_into
      @@extended_into ||= []
    end

    def self.included(base)
      included_into << base
    end

    def self.extended(base)
      extended_into << base
    end

    def self.enable_error_capture
      included_into.each do |base|
        base.send(:alias_method, :error_without_failure, :error)
        base.send(:alias_method, :error, :error_with_failure)
      end
      extended_into.each do |base|
        class << base
          alias_method :error_without_failure, :error
          alias_method :error, :error_with_failure
        end
      end
    end

    def self.disable_error_capture
      included_into.each do |base|
        base.send(:alias_method, :error, :error_without_failure)
      end
      extended_into.each do |base|
        class << base
          alias_method :error, :error_without_failure
        end
      end
    end


    def display_header(message="", new_line=true)
      return if message.to_s.strip == ""
      display("=== " + message.to_s.split("\n").join("\n=== "), new_line)
    end

    def display_object(object)
      case object
      when Array
        # list of objects
        object.each do |item|
          display_object(item)
        end
      when Hash
        # if all values are arrays, it is a list with headers
        # otherwise it is a single header with pairs of data
        if object.values.all? {|value| value.is_a?(Array)}
          object.keys.sort_by {|key| key.to_s}.each do |key|
            display_header(key)
            display_object(object[key])
            hputs
          end
        end
      else
        hputs(object.to_s)
      end
    end

    def hputs(string='')
      Kernel.puts(string)
    end

    def hprint(string='')
      Kernel.print(string)
      $stdout.flush
    end

    # produces a printf formatter line for an array of items
    # if an individual line item is an array, it will create columns
    # that are lined-up
    #
    # line_formatter(["foo", "barbaz"])                 # => "%-6s"
    # line_formatter(["foo", "barbaz"], ["bar", "qux"]) # => "%-3s   %-6s"
    #
    def line_formatter(array)
      cols = []
      array.each do |item|
        case item
        when Array then
          item.each_with_index { |val,idx| cols[idx] = [cols[idx]||0, val.length].max }
        else
          cols[0] = item.to_s.length
        end
      end
      cols.map { |col| "%-#{col}s" }.join("   ")
    end

    def styled_array(array)
      fmt = line_formatter(array)
      array.sort.each do |element|
        display(fmt % element)
      end
      display
    end

    def styled_header(header)
      display("=== #{header}")
    end

    def styled_hash(hash)
      max_key_length = hash.keys.map {|key| key.to_s.length}.max + 2
      hash.keys.sort {|x,y| x.to_s <=> y.to_s}.each do |key|
        title_cased_key = key.to_s.gsub("_", " ").split(" ").map do |word|
          word[0...1].upcase + word[1..-1]
        end.join(" ")
        case value = hash[key]
        when Array
          if value.empty?
            next
          else
            elements = value.sort {|x,y| x.to_s <=> y.to_s}
            display("#{title_cased_key}: ".ljust(max_key_length), false)
            display(elements[0])
            elements[1..-1].each do |element|
              display("#{' ' * max_key_length}#{element}")
            end
            if elements.length > 1
              display
            end
          end
        when nil
          next
        else
          display("#{title_cased_key}: ".ljust(max_key_length), false)
          display(value)
        end
      end
    end

    def string_distance(first, last)
      distances = [] # 0x0s
      0.upto(first.length) do |index|
        distances << [index] + [0] * last.length
      end
      distances[0] = 0.upto(last.length).to_a
      1.upto(last.length) do |last_index|
        1.upto(first.length) do |first_index|
          first_char = first[first_index - 1, 1]
          last_char = last[last_index - 1, 1]
          if first_char == last_char
            distances[first_index][last_index] = distances[first_index - 1][last_index - 1] # noop
          else
            distances[first_index][last_index] = [
              distances[first_index - 1][last_index],     # deletion
              distances[first_index][last_index - 1],     # insertion
              distances[first_index - 1][last_index - 1]  # substitution
            ].min + 1 # cost
            if first_index > 1 && last_index > 1
              first_previous_char = first[first_index - 2, 1]
              last_previous_char = last[last_index - 2, 1]
              if first_char == last_previous_char && first_previous_char == last_char
                distances[first_index][last_index] = [
                  distances[first_index][last_index],
                  distances[first_index - 2][last_index - 2] + 1 # transposition
                ].min
              end
            end
          end
        end
      end
      distances[first.length][last.length]
    end

  end
end
