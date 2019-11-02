require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'optparse'
require 'mechanize'
require 'pushover'

per_page = 25
scanning = true
yaml_file = "lfgss.yaml"
rewind = false
no_save = false
upload = false

# https://lfgss.microco.sm/api/v1/conversations/282005?limit=100&offset=7800

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
		page: [6250],
	}
end

posts = []
page = if rewind
	store[:tags].pop
	store[:page].pop
else
	store[:page].last
end

while scanning do
	puts "Getting page #{page}"
	doc = Nokogiri::HTML(open "https://www.lfgss.com/conversations/282005/?offset=#{page}")
	comments = doc.css("div.main div.content-body ul.list-comments > li.comment-item")
	posts += comments.map do |comment|
		header = comment.at_css("div.comment-item-header")
		body = comment.at_css("div.comment-item-body")

		{
			author: header.at_css('div.comment-item-author strong').text,
			permalink: header.at_css('div.comment-item-permalink a')['href'],
			links: body.css('a[href^="/comments/"]').map { |lnk| lnk['href'] },
			text: body.text,
			tags: body.css('a[href^="/search/?q=%23"]').map(&:text).map(&:downcase),
			images: body.css('img').map { |img| img['src'] }
		}

	end

	if comments.count == per_page
		page += 25
	else
		scanning = false
	end
end
store[:page] << page

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

	if post[:links].count > 4 and collector.count > 0
		puts "\e[31mVoting may have already started\e[0m"
		flawless = false
	end

	next unless post[:images].count > 0

	title = post[:text].lines.map(&:strip).reject(&:empty?).grep_v(/^\d+ Attachment$/).grep_v(current_tag).sort_by { |x| x.split.count }.first
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
		agent.user_agent = 'LFGSSBot (cyclotron3k)'
		agent.cookie_jar << Mechanize::Cookie.new(
			domain: 'www.lfgss.com',
			name: 'access_token',
			value: ENV['LFGSS_TOKEN'],
			path: '/',
			expires: (Date.today + 100).to_s,
		)
	end

	page = agent.get('https://www.lfgss.com/conversations/282005/newest/')
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

unless no_save
	File.open(yaml_file, 'w') do |file|
		puts "\nUpdating YAML file"
		file.write(YAML.dump store)
	end
end
