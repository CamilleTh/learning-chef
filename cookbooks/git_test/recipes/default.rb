#
# Cookbook Name:: git_test
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
#
# Cookbook Name:: gitlab-client
# Recipe:: default
#
# Copyright 2013, ADE for InTech S.A.
#
# All rights reserved - Do Not Redistribute
#

# 1. Create new repositories
# 2. For each new repositories, publish a sample project
# 3. Optionaly : store gitlab project id to node

masterAccessLevel 		= node['gitlab']['masterAccessLevel']
developerAccessLevel 	= node['gitlab']['developerAccessLevel']

gitlabRestBaseURL = "http://#{node['gitlab']['host']}:#{node['gitlab']['port']}/api/v3"
gitlabToken = node['gitlab']['token']
gitlabUser = node['gitlab']['user']

devaasDir = node['gitlab']['devaasDirectory']
defaultBranch = node['git']['defaultBranch']

directory "#{devaasDir}" do
	user 	"gitlab"
	action :create
end

directory "#{devaasDir}/tmp" do
	user 	"gitlab"
	action :create
end

git "#{devaasDir}/sampleapp" do
  repository node["git"]["sampleappRepo"]
  action :sync
  user "gitlab"
end

require 'rest_client'

applications = data_bag "applications"

applications.each do|app|
	appli = data_bag_item("applications", app)

	ruby_block "Create repository #{appli.id}" do
		currentRepos = JSON.parse(RestClient.get "#{gitlabRestBaseURL}/projects?private_token=#{gitlabToken}")
		currentUsers = JSON.parse(RestClient.get "#{gitlabRestBaseURL}/users?private_token=#{gitlabToken}")

		block do
			alreadyExists=false
			unless currentRepos.nil?
				alreadyExists = currentRepos.find{|r| r['name'] == appli['id']} != nil
			end
			Chef::Log.info "Repository #{appli['id']} exists ? #{alreadyExists}"
			if !alreadyExists
				Chef::Log.info "Create repository #{appli['id']} with default branch #{defaultBranch}"
				res = RestClient.post "#{gitlabRestBaseURL}/projects?private_token=#{gitlabToken}", 
								{ 
									'name' => appli['id'],
									'default_branch' => defaultBranch
								}.to_json, 
								:content_type => :json
				if res.code == 201
					newRepoId = JSON.parse(res)['id']
					Chef::Log.info "Repository #{appli['id']} created with id #{newRepoId}!"
					appli['masters'].each do|master|
						masterUser = currentUsers.find{|r| r['username'] == master}
						if masterUser != nil
							Chef::Log.info "Add user #{masterUser['name']} as master to repo #{appli['id']}"
							RestClient.post "#{gitlabRestBaseURL}/projects/#{newRepoId}/members?private_token=#{gitlabToken}",
							{ 'id'=> newRepoId,
							 	'user_id'=> masterUser['id'], 
							 	'access_level'=> masterAccessLevel
							}.to_json
						else
							Chef::Log.warning "Cannot find user #{master} in Gitlab"
						end
					end
					appli['developers'].each do|dev|
						devUser = currentUsers.find{|r| r['username'] == dev}
						if devUser != nil
							Chef::Log.info "Add user #{devUser['name']} as developer to repo #{appli['id']}"
							RestClient.post "#{gitlabRestBaseURL}/projects/#{newRepoId}/members?private_token=#{gitlabToken}",
							{ 'id'=> newRepoId,
							 	'user_id'=> devUser['id'], 
							 	'access_level'=> developerAccessLevel
							}.to_json
						else
							Chef::Log.warning "Cannot find user #{dev} in Gitlab"
						end
					end
				else
					Chef::Log.error "An error occured : response is #{res.code} with message #{res.to_str}"
				end
				if !alreadyExists
					sleep 5
					resources(:script => "Init repository #{appli.id}").run_action(:run)
					resources(:ruby_block => "Protect branches for repository #{appli.id}").run_action(:create, :delayed)
				end
			end
		end
		action :create
	end

	script "Init repository #{appli.id}" do
	  interpreter "bash"
	  user "gitlab"
	  cwd "#{devaasDir}/tmp"
	  code <<-EOH
	  	mkdir repo_#{appli.id}
	  	cd repo_#{appli.id}
	  	git clone git@localhost:#{gitlabUser}/#{appli.id}.git > /tmp/1.log 2> /tmp/2.log
	  	cd #{appli.id}
	  	cp -r #{devaasDir}/sampleapp/* .
	  	git add -A
	  	git commit -m "First commit"
	  	git branch #{defaultBranch}
	  	git checkout #{defaultBranch}
	  	git push origin #{defaultBranch}
	  	for branch in #{node['git']['additionalBranches'].map{|b| b['name']}.join ' '}
	  	do
	  		git branch $branch
	  		git push origin $branch
		  done
	  	cd #{devaasDir}/tmp
	  	rm -rf #{devaasDir}/tmp/repo_#{appli.id}
	  EOH
	  action :nothing
	end

	ruby_block "Protect branches for repository #{appli.id}" do
		block do
			currentRepos = JSON.parse(RestClient.get "#{gitlabRestBaseURL}/projects?private_token=#{gitlabToken}")
			repo = currentRepos.find{|r| r['name'] == appli.id}
			node['git']['additionalBranches'].each do|branch|
				if branch.protected
					Chef::Log.debug "Set branch #{branch.name} to protected for repository #{appli.id} with id #{repo['id']}"
					res=RestClient.put "#{gitlabRestBaseURL}/projects/#{repo['id']}/repository/branches/#{branch.name}/protect?private_token=#{gitlabToken}", {}.to_json
					if res.code==200
						Chef::Log.info "Branch #{branch.name} has been protected for repository #{appli.id}"
					else
						Chef::Log.error "An error occured : response is #{res.code} with message #{res.to_str}"
					end
				end
			end
		end
		action :nothing
	end

end
