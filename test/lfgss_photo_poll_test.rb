require 'test_helper'

class LfgssPhotoPollTest < Minitest::Test
	def setup
		@client = LfgssPhotoPoll.new no_save: true, yaml_file: './test/fixtures/test.yaml'
	end

	def stub_api_request(conversation, limit, offset)
		stub_request(
			:get,
			"https://lfgss.microco.sm/api/v1/conversations/#{conversation}?limit=#{limit}&offset=#{offset}"
		).to_return(
			status: 200,
			headers: {
				'Content-Type' => 'application/json',
			},
			body: File.new("./test/fixtures/#{conversation}-#{limit}-#{offset}.json"),
		)
	end

	def test_main
		stub_api_request 282005, 100, 7900
		stub_api_request 282005, 100, 8000

		assert_equal true, @client.process_posts

		assert_equal 57, @client.parsed_posts.count
		assert_equal '#green', @client.current_tag

		assert_equal(
			[
				"moocher - green paint ()",
				"https://www.lfgss.com/comments/15015439/",
				"graunch - green bark ()",
				"https://www.lfgss.com/comments/15016079/",
				"laurie - Compromise this ()",
				"https://www.lfgss.com/comments/15016127/",
				"jonuxuk - It's all a blur green ()",
				"https://www.lfgss.com/comments/15016160/",
				"skydancer - Are you feeling blue? ()",
				"https://www.lfgss.com/comments/15016180/",
				"yl - Strong green on cold morning and sketchy pumptrack ()",
				"https://www.lfgss.com/comments/15016346/",
				"WillMelling - green  turning to gold ()",
				"https://www.lfgss.com/comments/15016415/",
				"moorhen - green shirt ()",
				"https://www.lfgss.com/comments/15016558/",
				"Rik_Van_Looy - green and pleasant ()",
				"https://www.lfgss.com/comments/15016576/",
				"Landslide - Shall I lichen thee to a winter's day? ()",
				"https://www.lfgss.com/comments/15016584/"
			],
			@client.instance_variable_get(:@collector)
		)
	end

	def test_parsing
		post = <<~JSON
			{
				"id": 15007672,
				"itemType": "conversation",
				"itemId": 282005,
				"revisions": 1,
				"markdown": "![](https://i.imgur.com/SELEY1F.jpg) \\r\\n\\r\\n#peoplewedontknow - or rather, didn't",
				"html": "<p><img class=\\"ip\\" src=\\"https://i.imgur.com/SELEY1F.jpg\\"/></p>\\n\\n<p><a href=\\"/search/?q=%23peoplewedontknow\\">#peoplewedontknow</a> - or rather, didn&#39;t</p>\\n",
				"meta": {
					"created": "2019-12-01T23:48:26.541878Z",
					"createdBy": {
						"id": 120737,
						"siteId": 234,
						"userId": 71366,
						"profileName": "slothy",
						"visible": true,
						"avatar": "/api/v1/files/8dfe0e3eff229da7ec23b916cf243d84c2516e53.jpg",
						"meta": {
							"flags": {},
							"links": [
								{
									"rel": "self",
									"href": "/api/v1/profiles/120737"
								},
								{
									"rel": "site",
									"href": "/api/v1/sites/234"
								}
							]
						}
					},
					"editedBy": {
						"id": 120737,
						"siteId": 234,
						"userId": 71366,
						"profileName": "slothy",
						"visible": true,
						"avatar": "/api/v1/files/8dfe0e3eff229da7ec23b916cf243d84c2516e53.jpg",
						"meta": {
							"flags": {},
							"links": [
								{
									"rel": "self",
									"href": "/api/v1/profiles/120737"
								},
								{
									"rel": "site",
									"href": "/api/v1/sites/234"
								}
							]
						}
					},
					"flags": {
						"deleted": false,
						"moderated": false,
						"visible": true,
						"unread": true
					},
					"links": [
						{
							"rel": "self",
							"href": "/api/v1/comments/15007672"
						},
						{
							"rel": "conversation",
							"href": "/api/v1/conversations/282005",
							"title": "LFGSS weekly photography challenge"
						},
						{
							"rel": "up",
							"href": "/api/v1/conversations/282005",
							"title": "LFGSS weekly photography challenge"
						}
					]
				}
			}
		JSON

		assert_equal(
			{
				author:    "slothy",
				permalink: "/comments/15007672/",
				links:     0,
				text:      "\n\n#peoplewedontknow - or rather, didn't\n",
				tags:      ["#peoplewedontknow"],
				images:    1
			},
			@client.parse_post(JSON.parse post)
		)
	end
end
