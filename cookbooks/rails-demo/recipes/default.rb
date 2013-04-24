#
# Cookbook Name:: rails-demo
# Recipe:: default
#
# Copyright 2012, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
#

gem_package 'bundler' do
  action :install
end 

application "rails-demo" do
  path "/var/www/rails-apps/rails-demo"
  owner "vagrant"
  group "vagrant"
  repository "http://github.com/mulderp/chef-demo.git"
  rails do 
    bundler true
  end
  passenger_apache2
end
