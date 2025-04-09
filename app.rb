require 'sinatra'
require 'slim'
require 'sinatra/reloader'
require 'sqlite3'
require 'bcrypt'
#require_relative 'model/model.rb'

# Database setup
#DB = database_setup()
DB = SQLite3::Database.new 'db/albums.db'
DB.results_as_hash = true


# Create tables if they do not exist
# DB.execute <<-SQL
#   CREATE TABLE IF NOT EXISTS users (
#     id INTEGER PRIMARY KEY,
#     username TEXT UNIQUE,
#     password_hash TEXT
#   );
# SQL

# DB.execute <<-SQL
#   CREATE TABLE IF NOT EXISTS albums (
#     id INTEGER PRIMARY KEY,
#     title TEXT,
#     artist TEXT,
#     year INTEGER,
#     rating REAL,
#     listened_date TEXT,
#     user_id INTEGER,
#     FOREIGN KEY(user_id) REFERENCES users(id)
#   );
# SQL

# DB.execute <<-SQL
#   CREATE TABLE IF NOT EXISTS followers (
#     follower_id INTEGER,
#     followed_id INTEGER,
#     PRIMARY KEY (follower_id, followed_id),
#     FOREIGN KEY (follower_id) REFERENCES users(id),
#     FOREIGN KEY (followed_id) REFERENCES users(id)
#   );
# SQL

# Enable sessions
enable :sessions

# Helper methods
helpers do

  def user_exists?(id)
    result = DB.execute("SELECT 1 FROM users WHERE id = ? LIMIT 1", id).first
    !result.nil?
  end

  def current_user
    if session[:user_id]
      @current_user ||= DB.execute("SELECT * FROM users WHERE id = ?", session[:user_id]).first
    end
  end

  def logged_in?
    !current_user.nil?
  end

  def is_following?(follower_id, followed_id)
    !DB.execute("SELECT * FROM followers WHERE follower_id = ? AND followed_id = ?", [follower_id, followed_id]).empty?
  end
end

# Routes
get '/' do
  if logged_in?
    albums = DB.execute("SELECT * FROM albums WHERE user_id = ? ORDER BY id DESC", current_user['id'])
    slim :index, locals: { albums: albums }
    redirect "/profiles/#{current_user['id']}" ## fungerar typ idk 
  else
    redirect '/login'
  end
end

get '/new' do
  redirect '/login' unless logged_in?
  slim :new
end

post '/albums' do
  redirect '/login' unless logged_in?
  rating = params[:rating].to_f
  listened_date = params[:listened_date]
  DB.execute("INSERT INTO albums (title, artist, year, rating, listened_date, user_id) VALUES (?, ?, ?, ?, ?, ?)", [params[:title], params[:artist], params[:year], rating, listened_date, current_user['id']])
  redirect '/'
end

get '/albums/:id/edit' do
  redirect '/login' unless logged_in?
  album = DB.execute("SELECT * FROM albums WHERE id = ? AND user_id = ?", [params[:id], current_user['id']]).first
  if album
    slim :edit, locals: { album: album }
  else
    redirect '/'
  end
end

post '/albums/:id/delete' do
  redirect '/login' unless logged_in?
  DB.execute("DELETE FROM albums WHERE id = ? AND user_id = ?", [params[:id], current_user['id']])
  redirect '/'
end



post '/delete_user/:id/delete' do
  redirect '/login' unless logged_in?
  DB.execute("DELETE FROM users WHERE id = ?", [params[:id]])
  redirect '/'
end


post '/albums/:id' do
  redirect '/login' unless logged_in?
  rating = params[:rating].to_f
  listened_date = params[:listened_date]
  DB.execute("UPDATE albums SET title = ?, artist = ?, year = ?, rating = ?, listened_date = ? WHERE id = ? AND user_id = ?", [params[:title], params[:artist], params[:year], rating, listened_date, params[:id], current_user['id']])
  redirect '/'
end

# Follow a user
post '/follow/:id' do
  redirect '/login' unless logged_in?
  followed_id = params[:id].to_i
  if followed_id != current_user['id'] && !is_following?(current_user['id'], followed_id)
    DB.execute("INSERT INTO followers (follower_id, followed_id) VALUES (?, ?)", [current_user['id'], followed_id])
  end
  redirect "/profiles/#{followed_id}"
end

# Unfollow a user
post '/unfollow/:id' do
  redirect '/login' unless logged_in?
  followed_id = params[:id].to_i
  DB.execute("DELETE FROM followers WHERE follower_id = ? AND followed_id = ?", [current_user['id'], followed_id])
  redirect "/profiles/#{followed_id}"
end

# Show followers of a user
get '/followers/:id' do
  user_id = params[:id].to_i
  user = DB.execute("SELECT * FROM users WHERE id = ?", user_id).first
  followers = DB.execute("SELECT users.* FROM followers JOIN users ON followers.follower_id = users.id WHERE followers.followed_id = ?", user_id)
  slim :"follow/followers", locals: { followers: followers, user: user}
end

# Show who a user is following
get '/following/:id' do
  user_id = params[:id].to_i
  user = DB.execute("SELECT * FROM users WHERE id = ?", user_id).first
  following = DB.execute("SELECT users.* FROM followers JOIN users ON followers.followed_id = users.id WHERE followers.follower_id = ?", user_id)
  slim :"follow/following", locals: { following: following, user: user}
end

# Profile page
get '/profiles/:id' do
  user_id = params[:id].to_i
  user = DB.execute("SELECT * FROM users WHERE id = ?", user_id).first

  followers_count = DB.execute(<<-SQL, user_id).first['count']
    SELECT COUNT(*) AS count
    FROM followers
    JOIN users ON followers.follower_id = users.id
    WHERE followers.followed_id = ?
  SQL

  following_count = DB.execute(<<-SQL, user_id).first['count']
    SELECT COUNT(*) AS count
    FROM followers
    JOIN users ON followers.followed_id = users.id
    WHERE followers.follower_id = ?
  SQL

  # followers_count = DB.execute("SELECT COUNT(*) AS count FROM followers WHERE followed_id = ?", user_id).first['count']
  # following_count = DB.execute("SELECT COUNT(*) AS count FROM followers WHERE follower_id = ?", user_id).first['count']
  is_following = logged_in? && is_following?(current_user['id'], user_id)
  albums = DB.execute("SELECT * FROM albums WHERE user_id = ? ORDER BY id DESC", user_id)
  slim :"profile/profile", locals: { user: user, albums: albums, followers_count: followers_count, following_count: following_count, is_following: is_following }
end

get '/login' do
  slim :login
end

post '/login' do
  user = DB.execute("SELECT * FROM users WHERE username = ?", params[:username]).first
  if user && BCrypt::Password.new(user['password_hash']) == params[:password]
    session[:user_id] = user['id']
    redirect '/'
  else
    slim :login, locals: { error: 'Invalid username or password' }
  end
end

get '/signup' do
  slim :signup
end

post '/signup' do
  password_hash = BCrypt::Password.create(params[:password])
  begin
    DB.execute("INSERT INTO users (username, password_hash) VALUES (?, ?)", [params[:username], password_hash])
    user = DB.execute("SELECT * FROM users WHERE username = ?", params[:username]).first
    session[:user_id] = user['id']
    redirect '/'
  rescue SQLite3::ConstraintException
    slim :signup, locals: { error: 'Username already exists. Please try another.' }
  end
end

get '/logout' do
  session.clear
  redirect '/login'
end

get '/profiles' do
  query = params[:query]
  if query && !query.empty?
    users = DB.execute("SELECT id, username FROM users WHERE username LIKE ?", "%#{query}%")
  else
    users = DB.execute("SELECT id, username FROM users")
  end
  slim :"profile/profiles", locals: { users: users, query: query }
end
