class IrcNotice

  def initialize
    @data = YAML.load_file('app/config/irc.yml')
  end

  #string   :server, :port, :room, :nick, :branch_regexes, :nickserv_password
  #password :password
  #boolean  :ssl, :message_without_join, :no_colors, :long_url, :notice
  #white_list :server, :port, :room, :nick

  #default_events :push, :pull_request
  
  def receive_push(json_data)
    post_data = JSON.parse(json_data)
    #return unless branch_name_matches?(post_data["commits"].first["branch"])

    messages = []
    messages << "#{irc_push_summary_message(post_data)}: #{fmt_url(post_data["canon_url"] << post_data["repository"]["absolute_url"] << 'commits/' << post_data["commits"].first["node"])}"
    messages += post_data["commits"].first(3).map {
        |commit| self.irc_format_commit_message(commit, post_data)
    }
    send_messages messages
  end

  def send_messages(messages)
    messages = Array(messages)

    if @data['no_colors'].to_i == 1
      messages.each{|message|
        message.gsub!(/\002|\017|\026|\037|\003\d{0,2}(?:,\d{1,2})?/, '')}
    end

    rooms = @data['room'].to_s
    if rooms.empty?
      raise  "No rooms: #{rooms.inspect}"
      return
    end

    rooms   = rooms.gsub(",", " ").split(" ").map{|room| room[0].chr == '#' ? room : "##{room}"}
    botname = @data['nick'].to_s.empty? ? "BB-irc-notice#{rand(200)}" : @data['nick']
    command = @data['notice'].to_i == 1 ? 'NOTICE' : 'PRIVMSG'

    irc_password("PASS", @data['password']) if !@data['password'].to_s.empty?
    irc_puts "NICK #{botname}"
    irc_puts "USER #{botname} 8 * :BB-irc-notice IRCBot"

    loop do
      case irc_gets
      when / 00[1-4] #{Regexp.escape(botname)} /
        break
      when /^PING\s*:\s*(.*)$/
        irc_puts "PONG #{$1}"
      end
    end

    nickserv_password = @data['nickserv_password'].to_s
    if !nickserv_password.empty?
      irc_password("PRIVMSG NICKSERV :IDENTIFY", nickserv_password)
      loop do
        case irc_gets
        when /^:NickServ/i
          # NickServ responded somehow.
          break
        when /^PING\s*:\s*(.*)$/
          irc_puts "PONG #{$1}"
        end
      end
    end

    without_join = @data['message_without_join'].to_i == 1
    rooms.each do |room|
      room, pass = room.split("::")
      irc_puts "JOIN #{room} #{pass}" unless without_join

      messages.each do |message|
        irc_puts "#{command} #{room} :#{message}"
      end

      irc_puts "PART #{room}" unless without_join
    end

    irc_puts "QUIT"
    irc_gets until irc_eof?
  rescue SocketError => boom
    if boom.to_s =~ /getaddrinfo: Name or service not known/
      raise_config_error 'Invalid host'
    elsif boom.to_s =~ /getaddrinfo: Servname not supported for ai_socktype/
      raise_config_error 'Invalid port'
    else
      raise
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    raise_config_error 'Invalid host'
  rescue OpenSSL::SSL::SSLError
    raise_config_error 'Host does not support SSL'
  end

  def irc_gets
    response = readable_irc.gets
    response
  end

  def irc_eof?
    readable_irc.eof?
  end

  def irc_password(command, password)
    real_command = "#{command} #{password}"
    debug_command = "#{command} #{'*' * password.size}"
    irc_puts(real_command, debug_command)
  end

  def irc_puts(command, debug_command=command)
    writable_irc.puts command
  end

  def irc
    @irc ||= begin
      socket = TCPSocket.open(@data['server'], port)
      socket = new_ssl_wrapper(socket) if use_ssl?
      socket
    end
  end

  alias readable_irc irc
  alias writable_irc irc

  def new_ssl_wrapper(socket)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.connect
    ssl_socket
  end

  def use_ssl?
    @data['ssl'].to_i == 1
  end

  def default_port
    use_ssl? ? 9999 : 6667
  end

  def port
    @data['port'] ? @data['port'].to_i : default_port
  end

  def url
    @data['long_url'].to_i == 1 ? summary_url : shorten_url(summary_url)
  end

  ### IRC message formatting.  For reference:
  ### \002 bold   \003 color   \017 reset  \026 italic/reverse  \037 underline
  ### 0 white           1 black         2 dark blue         3 dark green
  ### 4 dark red        5 brownish      6 dark purple       7 orange
  ### 8 yellow          9 light green   10 dark teal        11 light teal
  ### 12 light blue     13 light purple 14 dark gray        15 light gray

  def fmt_url(s)
    "\00302\037#{s}\017"
  end

  def fmt_repo(s)
    "\00313#{s}\017"
  end

  def fmt_name(s)
    "\00315#{s}\017"
  end

  def fmt_branch(s)
    "\00306#{s}\017"
  end

  def fmt_tag(s)
    "\00306#{s}\017"
  end

  def fmt_hash(s)
    "\00314#{s}\017"
  end

  def irc_push_summary_message(post_data)
    message = []
    message << "\00301[#{fmt_repo post_data["repository"]["name"]}\00301] #{fmt_name post_data["user"]}"
    num = post_data["commits"].size
    message << "pushed \002#{num}\017 new commit#{num != 1 ? 's' : ''} to #{fmt_branch post_data["commits"].last["branch"]}"

    message.join(' ')
  end

  def irc_format_commit_message(commit, post_data)
    short  = commit['message'].split("\n", 2).first.to_s
    short += '...' if short != commit['message']

    author = commit['raw_author'].gsub(/^([\w\s]*?)( <.*$|$)/i, '\1')
    sha1   = commit['node']

    "#{fmt_repo post_data["repository"]["name"]}/#{fmt_branch commit['branch']} #{fmt_hash sha1[0..6]} " +
    "#{fmt_name author}: #{short}"
  end

  def branch_name_matches?(branch_name)
    return true if @data['branch_regexes'].nil?
    return true if @data['branch_regexes'].strip == ""
    branch_regexes = @data['branch_regexes'].split(',')
    branch_regexes.each do |regex|
      return true if Regexp.new(regex) =~ branch_name
    end
    false
  end
end
