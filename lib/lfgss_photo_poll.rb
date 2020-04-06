require 'yaml'
require 'optparse'
require 'nokogiri'
require 'mechanize'
require 'pushover'
require 'json'

require 'lfgss_photo_poll/version'

class LfgssPhotoPoll

	attr_reader :rewind, :no_save, :upload, :user_agent, :limit, :conversation_id, :yaml_file
	attr_writer :offset, :last_post_id

	def initialize(
		rewind: false,
		no_save: false,
		upload: false,
		yaml_file: 'lfgss.yaml',
		pushover_user: ENV['PUSHOVER_USER'],
		pushover_token: ENV['PUSHOVER_TOKEN'],
		lfgss_token: ENV['LFGSS_TOKEN']
	)

		@rewind         = rewind
		@no_save        = no_save
		@upload         = upload
		@yaml_file      = yaml_file
		@pushover_user  = pushover_user
		@pushover_token = pushover_token
		@lfgss_token    = lfgss_token

		@user_agent = 'LFGSSBot (cyclotron3k)'
		@limit = 100
		@conversation_id = 282005

		@new_comments = nil
		@current_tag = nil
	end

	def store
		@store ||= if File.exist?(yaml_file)
			YAML.load_file yaml_file
		else
			# bootstrap
			puts "YAML file #{@yaml_file} missing"
			{
				tags: ['#calm'],
				last_post_id: [12345],
				offset: [7600],
			}
		end
	end

	def last_post_id
		@last_post_id ||= store[:last_post_id].last
	end

	def offset
		@offset ||= store[:offset].last
	end

	def new_comments
		return @new_comments if @new_comments
		@new_comments = []
		uri = URI("https://lfgss.microco.sm/api/v1/conversations/#{conversation_id}")
		Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
			run = true
			while run
				uri.query = URI.encode_www_form limit: limit, offset: offset
				request = Net::HTTP::Get.new uri, 'User-Agent' => user_agent
				puts uri

				response = http.request request # Net::HTTPResponse object
				raise "#{response.class} #{response.body}" unless response.is_a? Net::HTTPSuccess
				data = JSON.parse response.body

				@new_comments += data.dig("data", "comments", "items").select { |x| x["id"] > last_post_id }
				self.last_post_id = @new_comments.last["id"] if @new_comments.any?

				run = if data.dig("data", "comments", "maxOffset") >= offset + limit
					self.offset += limit
					true
				else
					false
				end
			end
		end
		@new_comments
	end

	def parsed_posts
		@parsed_posts ||= new_comments.map { |post| parse_post post }
	end

	def parse_post(post)
		doc = Nokogiri::HTML post['html']

		{
			author: post.dig('meta', 'createdBy', 'profileName'),
			permalink: "/comments/#{post['id']}/",
			links: doc.css('a[href^="/comments/"]').count,
			text: doc.text,
			tags: post['markdown'].scan(/#\w+/).map(&:downcase).uniq,
			images: (post['attachments'] || 0 ) + doc.css('img').count
		}
	end

	def current_tag
		return @current_tag if @current_tag
		new_tags = parsed_posts.flat_map { |x| x[:tags] }.each_with_object(Hash.new 0) { |x, h| h[x] += 1 }
		store[:tags].each { |x| new_tags.delete x }

		if new_tags.empty?
			raise "New tag not identified"
		end

		@current_tag = new_tags.max_by { |_, v| v }.first
		puts "Identified current tag: #{current_tag}"
		@current_tag
	end

	def process_posts
		@collector = []
		flawless = true
		parsed_posts.each do |post|

			if post[:links] > 4 and @collector.count > 0
				puts "\e[31mVoting may have already started\e[0m"
				flawless = false
			end

			next unless post[:images] > 0

			title = post[:text].lines.map(&:strip).reject(&:empty?).grep_v(/\A#{current_tag}\z/i).sort_by { |x| x.split.count }.first
			if title
				title = " - " + title.gsub(/#{current_tag}/i, current_tag[1..-1])
			end

			if post[:tags].count == 0
				puts "\e[90m#{post[:author]}#{title} ()\e[0m \e[31m[MISSING TAG]\e[0m"
				puts "\e[90mhttps://www.lfgss.com#{post[:permalink]}\e[0m"
				# flawless = false
			elsif post[:tags].include?(current_tag)
				@collector << "#{post[:author]}#{title} ()"
				puts @collector.last
				@collector << "https://www.lfgss.com#{post[:permalink]}"
				puts @collector.last
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

		if flawless
			post_to_lfgss
		elsif upload
			puts "\e[31mRefusing to upload to LFGSS\e[0m"

			pushover 'Failed to post message to LFGSS',	priority: 1
		end

		save_store

		flawless
	end

	def post_to_lfgss

		if upload and @collector.size > 0

			puts "\e[34mPosting text to LFGSS\e[0m"
			agent = Mechanize.new do |a|
				a.user_agent = user_agent
				a.cookie_jar << Mechanize::Cookie.new(
					domain: 'www.lfgss.com',
					name: 'access_token',
					value: @lfgss_token,
					path: '/',
					expires: (Date.today + 100).to_s,
				)
			end

			page = agent.get("https://www.lfgss.com/conversations/#{conversation_id}/newest/")
			# page = agent.get('https://www.lfgss.com/conversations/253639/newest/') # test page
			form = page.form_with(action: '/comments/create/')
			form.markdown = "#{current_tag}\n\n" + @collector.join("\n")
			page = agent.submit form

			pushover 'Message posted to LFGSS ok'

			puts "\e[33mDone"

		end

	end

	def save_store
		store[:offset] = (store[:offset] | [offset]).compact
		store[:tags] = (store[:tags] | [current_tag]).compact
		store[:last_post_id] = (store[:last_post_id] | [last_post_id]).compact

		unless no_save
			File.open(yaml_file, 'w') do |file|
				puts "\nUpdating YAML file"
				file.write(YAML.dump store)
			end
		end
	end

	def pushover(message, priority: 0)
		raise if Pushover::Message.new(
			user: @pushover_user,
			token: @pushover_token,
			message: message,
			priority: priority,
		).push.status != 1
	end

end
