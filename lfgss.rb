require 'yaml'
require 'optparse'
require 'mechanize'
require 'pushover'
require 'json'

["PUSHOVER_USER", "PUSHOVER_TOKEN", "LFGSS_TOKEN"].reject do |k|
	ENV.key? k
end.tap do |missing|
	warn "Missing environment variables: #{missing}" if missing.any?
end

yaml_file = "lfgss.yaml"
rewind = false
no_save = false
upload = false
user_agent = 'LFGSSBot (cyclotron3k)'

# `snapctl get username`
# `snapctl get password`
# `snapctl get conversation_id`

OptionParser.new do |opts|
	opts.banner = "Usage: lfgss.rb [options]"

	opts.on("-?", "--help", "Prints this help") do
		puts opts
		exit
	end

	opts.on("-r", "--rewind", "Rewind to the previous state") do
		rewind = true
	end

	opts.on("-n", "--no-save", "Don't save any changes") do
		no_save = true
	end

	opts.on("-p", "--post", "Automatically post the output") do
		upload = true
	end
end.parse!


store = if File.exist?(yaml_file)
	YAML.load_file yaml_file
else
	{
		tags: ['#calm'],
		last_post_id: [12345],
		offset: [7100],
	}
end

last_post_id, offset = if rewind
	store[:tags].pop
	[
		store[:last_post_id].pop,
		store[:offset].pop,
	]
else
	[
		store[:last_post_id].last,
		store[:offset].last,
	]
end

posts = []
limit = 100
conversation_id = 282005

uri = URI("https://lfgss.microco.sm/api/v1/conversations/#{conversation_id}")
Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
	run = true
	while run
		uri.query = URI.encode_www_form limit: limit, offset: offset
		request = Net::HTTP::Get.new uri, 'User-Agent' => user_agent
		puts uri

		response = http.request request # Net::HTTPResponse object
		run = if response.is_a?(Net::HTTPSuccess)
			data = JSON.parse response.body

			posts += data.dig("data", "comments", "items").select do |post|
				if post["id"] > last_post_id
					last_post_id = post["id"]
					true
				else
					false
				end
			end

			if data.dig("data", "comments", "maxOffset") >= offset + limit
				offset += limit
				true
			else
				false
			end

		else
			puts "\e[31m#{response.body}\e[0m"
			raise "#{response.class} #{response.body}"
			false
		end

	end
end

posts.map! do |post|
	{
		author: post.dig("meta", "createdBy", "profileName"),
		permalink: "/comments/#{post['id']}/",
		links: post["markdown"].scan(/\/comments\/\d{6,8}\//).count,
		text: post["markdown"],
		tags: post["markdown"].scan(/#\w+/).map(&:downcase).uniq,
		images: (post["attachments"] || 0 ) + post["html"].scan(/<img [^>]*src="[^"]*\.(?:tiff|png|jpe?g)"/i).count
	}
end

store[:offset] << offset

new_tags = posts.flat_map { |x| x[:tags] }.each_with_object(Hash.new 0) { |x, h| h[x] += 1 }
store[:tags].each { |x| new_tags.delete x }

begin
	current_tag = new_tags.max_by { |_, v| v }.first
	puts "Identified current tag: #{current_tag}"
rescue NoMethodError
	puts "Couldn't identify a new tag"
	exit
end

collector = []
flawless = true
posts.each do |post|

	if post[:links] > 4 and collector.count > 0
		puts "\e[31mVoting may have already started\e[0m"
		flawless = false
	end

	next unless post[:images] > 0

	title = post[:text].lines.map(&:strip).reject(&:empty?).grep_v(current_tag).sort_by { |x| x.split.count }.first
	if title
		title = " - " + title.gsub(/#{current_tag}/i, current_tag[1..-1])
	end

	if post[:tags].count == 0
		puts "\e[90m#{post[:author]}#{title} ()\e[0m \e[31m[MISSING TAG]\e[0m"
		puts "\e[90mhttps://www.lfgss.com#{post[:permalink]}\e[0m"
		# flawless = false
	elsif post[:tags].include?(current_tag)
		collector << "#{post[:author]}#{title} ()"
		puts collector.last
		collector << "https://www.lfgss.com#{post[:permalink]}"
		puts collector.last
	elsif (post[:tags] - store[:tags]).count == 0
		# do nothing - it's related to a previous tag
		# puts "\e[33mIgnoring post with #{post[:tags]}\e[0m"
		next
	else
		# possible mis-spelling
		puts "\e[90m#{post[:author]}#{title} ()\e[0m \e[31m[TAGS: #{post[:tags].join ', '}]\e[0m"
		puts "\e[90mhttps://www.lfgss.com#{post[:permalink]}\e[0m"
		flawless = false
	end

end

if upload and flawless and collector.size > 0

	puts "\e[34mPosting text to LFGSS\e[0m"
	agent = Mechanize.new do |agent|
		agent.user_agent = user_agent
		agent.cookie_jar << Mechanize::Cookie.new(
			domain: 'www.lfgss.com',
			name: 'access_token',
			value: ENV['LFGSS_TOKEN'],
			path: '/',
			expires: (Date.today + 100).to_s,
		)
	end

	page = agent.get('https://www.lfgss.com/conversations/#{conversation_id}/newest/')
	# page = agent.get('https://www.lfgss.com/conversations/253639/newest/') # test page
	form = page.form_with(action: "/comments/create/")
	form.markdown = "#{current_tag}\n\n" + collector.join("\n")
	page = agent.submit form

	raise if Pushover::Message.create(
		user: ENV['PUSHOVER_USER'],
		token: ENV['PUSHOVER_TOKEN'],
		message: 'Message posted to LFGSS ok',
		priority: 0,
	).push.status != 1

	puts "\e[33mDone"

elsif upload and !flawless
	puts "\e[31mRefusing to upload to LFGSS\e[0m"

	raise if Pushover::Message.create(
		user: ENV['PUSHOVER_USER'],
		token: ENV['PUSHOVER_TOKEN'],
		message: 'Failed to post message to LFGSS',
		priority: 1,
	).push.status != 1
end

store[:tags] << current_tag
store[:last_post_id] << last_post_id

unless no_save
	File.open(yaml_file, 'w') do |file|
		puts "\nUpdating YAML file"
		file.write(YAML.dump store)
	end
end
