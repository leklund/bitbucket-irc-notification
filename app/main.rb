require 'rubygems'
require 'sinatra'
require 'json'

require_relative 'lib/irc_notice.rb'


use Rack::Auth::Basic, "Protected Area" do |username, password|
    username == 'user' && password == 'pass'
end

get '/' do
   irc = IrcNotice.new
   irc.receive_push(params[:payload])
   200
end

get '/test' do
  test_json = <<EOS
{
"canon_url": "https://bitbucket.org", 
    "commits": [
        {
            "author": "marcus", 
            "branch": "master", 
            "files": [
                {
                    "file": "somefile.py", 
                    "type": "modified"
                }
            ], 
            "message": "Added some more things to somefile.py", 
            "node": "620ade18607a", 
            "parents": [
                "702c70160afc"
            ], 
            "raw_author": "Marcus Bertrand <marcus@somedomain.com>", 
            "raw_node": "620ade18607ac42d872b568bb92acaa9a28620e9", 
            "revision": null, 
            "size": -1, 
            "timestamp": "2012-05-30 05:58:56", 
            "utctimestamp": "2012-05-30 03:58:56+00:00"
        }
    ], 
    "repository": {
        "absolute_url": "/marcus/project-x/", 
        "fork": false, 
        "is_private": true, 
        "name": "Project X", 
        "owner": "marcus", 
        "scm": "git", 
        "slug": "project-x", 
        "website": "https://atlassian.com/"
    }, 
    "user": "marcus"
}
EOS
  irc = IrcNotice.new
  irc.receive_push(test_json)
  200
end
