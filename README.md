ActionCable
===========

Example app for Rails 5 ActionCable

### New app
Start new Rails 5 application
```
rails _5.0.0.rc1_ new battle-ship -d mysql
cd battle-ship
```
### Prepare database
Update your `config/database.yml` and run
```
rails db:create
```
# Define models
We are going to have only two models
```
rails g model User name:string opponent_id:integer
rails g model Battle user:references matrix:text
rails db:migrate
```
# models/battle.rb
```ruby
class Battle < ApplicationRecord
  belongs_to :user

  EMPTY = 0
  SHIP = 1
  MISS = 2
  HIT = 3
  MATRIX_SIZE = 3

  serialize :matrix

  def start_game
    populate_matrix
  end

  def guess x, y
    return false if self.matrix[x].nil? || self.matrix[x][y].nil?

    is_hit = self.matrix[x][y] == SHIP

    self.matrix[x][y] = is_hit ? HIT : MISS

    self.save
    is_hit
  end

  def all_ships_sunk?
    self.matrix.select { |c| c.select { |r| r == SHIP }.any? }.any? == false
  end

  private

  def populate_matrix
    self.matrix = []
    (0..Battle::MATRIX_SIZE-1).each do |row|
      self.matrix[row] = [EMPTY] * Battle::MATRIX_SIZE
      self.matrix[row][(rand * Battle::MATRIX_SIZE).to_i] = SHIP
    end
    self.save
  end
end
```

### models/user.rb
```ruby
class User < ApplicationRecord
  has_many :battles, dependent: :destroy
  scope :opponents_waiting, -> { where(opponent_id: nil) }

  def opponent
    User.find_by id: self.reload.opponent_id
  end

  def assign_opponent
    opponent = User.opponents_waiting.where('id != ?', self.id).first
    unless opponent.nil?
      self.update(opponent_id: opponent.id)
      opponent.update(opponent_id: self.id)
    end
    opponent
  end

  def disconnect_opponent
    _opponent = opponent
    _opponent.update(opponent_id: nil) unless _opponent.nil?
    self.update(opponent_id: nil)
  end

  def channel_name
    "game_channel_#{self.id}"
  end

  def start_battle
    battle = self.battles.new
    battle.start_game
    battle.save
    battle
  end
end
```

# Authentication
We are going to create a new file `app/controllers/concerns/authentication.rb`
```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :ensure_authenticated_user
  end

  private
  def ensure_authenticated_user
    authenticate_user(cookies.signed[:user_id]) || redirect_to(new_session_url)
  end

  def authenticate_user(user_id)
    if authenticated_user = User.find_by(id: user_id)
      cookies.signed[:user_id] ||= authenticated_user.id
      @current_user = authenticated_user
    end
  end

  def unauthenticate_user
    ActionCable.server.disconnect(current_user: @current_user)
    User.find(@current_user.id).destroy
    @current_user = nil
    cookies.delete(:user_id)
  end
end
```

### app/controllers/application_controller.rb
```ruby
class ApplicationController < ActionController::Base
  include Authentication
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
end

```
Now we are going to create a sessions controller `app/controllers/sessions_controller.rb`. It will enable login/logout features.
```ruby
class SessionsController < ApplicationController
  skip_before_action :ensure_authenticated_user, only: %i( new create )

  def new
    @user = User.new
  end

  def create
    user = User.find_or_create_by!(user_auth_params)
    authenticate_user(user.id)
    redirect_to :root
  end

  def destroy
    unauthenticate_user
    redirect_to new_session_url
  end

  protected

  def user_auth_params
    params.require(:user).permit(:name)
  end
end
```

And appropriate view file `app/views/sessions/new.html.erb`
```erb
<h1>Please enter your name</h1>

<%= form_for @user, url: session_path do |f| %>
    <div class="form-group">
      <%= f.label :name, 'User Name', class: 'control-label' %>
      <%= f.text_field :name, class: 'form-control' %>
    </div>
    <div class="form-action">
      <%= f.submit 'Start game', class: 'btn btn-success' %>
    </div>
<% end %>

```

GameController is going to be our root `app/controllers/game_controller.rb`
```ruby
class GameController < ApplicationController
  def index
  end
end
```
### config/routes.rb
Don't forget to update your routes.
```ruby
root 'game#index'
resource  :session
```

### Identify connection with current user
### app/channels/application_cable/connection.rb

```ruby
    # Be sure to restart your server when you modify this file. Action Cable runs in a loop that does not support auto reloading.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      logger.add_tags 'ActionCable', current_user.name
    end

    protected
    def find_verified_user
      if verified_user = User.find_by(id: cookies.signed[:user_id])
        verified_user
      else
        reject_unauthorized_connection
      end
    end
  end
end

```
### app/views/game/_matrix.html.erb
Matrix partial is going to render a matrix
```erb
<% (0..2).each do |row| %>
    <div class="battleship-row">
      <% (0..2).each do |cell| %>
          <div class="battleship-cell <%= 'disabled' if disabled %>"
               data-x="<%= row %>"
               data-y="<%= cell %>"
          ></div>
      <% end %>
    </div>
<% end %>
```

# Example
Update file `app/views/game/index.html.erb`
```erb
<%= render 'layouts/header' %>

<div class="row">
  <div class="col-md-5">
    <div class="left-side">
      <h3>My Battleships</h3>

      <div id="my-battleship">
        <%= render partial: 'matrix', locals: {disabled: true} %>
      </div>
    </div>
  </div>
  <div class="col-md-7">
    <div class="right-side">
      <h3>Opponent's Battleships</h3>

      <div id="opponent-battleship">
        <div id="my-turn">
          <span>Waiting for opponent's move</span>
        </div>
        <%= render partial: 'matrix', locals: {disabled: false} %>
      </div>
    </div>
  </div>
</div>

<div id="game-over">
  <%= image_tag "loserville.gif", class: 'loser' %>
  <%= image_tag "winner.gif", class: 'winner' %>
</div>

<div id="game-not-started">
  <span>Waiting for opponent</span>
</div>
```


### Generate Game channel
We are going to generate a `game` channel with public method `guess`
```
rails g channel game guess
```
## app/channels/game_channel.rb
and let's put some logic in our game channel.
```ruby
# Be sure to restart your server when you modify this file. Action Cable runs in a loop that does not support auto reloading.
class GameChannel < ApplicationCable::Channel
  def subscribed
    stream_from current_user.channel_name

    if opponent = current_user.assign_opponent
      current_user.battles.destroy_all
      opponent.battles.destroy_all
      ActionCable.server.broadcast current_user.channel_name, {battle_field: current_user.start_battle, my_turn: false}
      ActionCable.server.broadcast opponent.channel_name, {battle_field: opponent.start_battle, my_turn: true}
    else
      ActionCable.server.broadcast current_user.channel_name, {waiting_for_opponent: true}
    end
  end

  def unsubscribed
    current_user.disconnect_opponent
  end

  def guess(data)
    response = {
        guess: {
            x: data['x'],
            y: data['y'],
            guessed_by: current_user
        }
    }

    opponent = current_user.opponent

    unless opponent.nil?
      opponent_battle_field = opponent.battles.first
      unless opponent_battle_field.nil?
        is_hit = opponent_battle_field.guess(data['x'], data['y'])
        game_over = opponent_battle_field.all_ships_sunk?

        response[:guess][:is_hit] = is_hit
        response[:guess][:is_game_over] = game_over
        response[:guess][:owner] = false
        response[:my_turn] = is_hit == false
        response[:guess][:won] = false if game_over

        ActionCable.server.broadcast opponent.channel_name, response
      end

      response[:my_turn] = response[:guess][:is_hit]
      response[:guess][:owner] = true
      response[:guess][:won] = true if game_over

      ActionCable.server.broadcast current_user.channel_name, response
    end
  end
end

```

## app/assets/javascripts/channels/game.coffee
and let's define what is going to happen on client side as well
```coffeescript
App.game = App.cable.subscriptions.create "GameChannel",
  connected: ->
    # Called when the subscription is ready for use on the server
    console.log('connected')

  disconnected: ->
    # Called when the subscription has been terminated by the server

  myTurn: false,
  received: (data) ->
    $("#game-not-started").hide()

    if data.battle_field

      App.game.myTurn = data.my_turn
      if data.my_turn
        $("#my-turn").hide()
      else
        $("#my-turn").show()

      $("#game-over").hide()
      App.game.displayMyMatrix(data.battle_field.matrix)
      App.game.displayOpponentMatrix()
    else if data.opponent_left
      alert('Oponent left')

    else if data.guess
      response = data.guess
      el = null
      if response.owner
        el = $("#opponent-battleship .battleship-cell[data-x='" + response.x + "'][data-y='" + response.y + "']")
      else
        el = $("#my-battleship .battleship-cell[data-x='" + response.x + "'][data-y='" + response.y + "']")

      if response.is_hit
        el.removeClass('empty ship miss hit').addClass('hit disabled')
      else
        el.removeClass('empty ship miss hit').addClass('miss disabled')

      App.game.myTurn = data.my_turn

      if response.is_game_over
        $("#game-over").show()
        if response.won
          $("#game-over").addClass "won"

      if data.my_turn
        $("#my-turn").hide()
      else
        $("#my-turn").show()
    else if data.waiting_for_opponent
      $("#game-not-started").show()

  displayMyMatrix: (data) =>
    App.game.displayMatrix('my-battleship', data)

  displayOpponentMatrix: () =>
    App.game.displayMatrix('opponent-battleship', [[0, 0, 0], [0, 0, 0], [0, 0, 0]])

  displayMatrix: (id, data) =>
    $.each data, (x, cells) =>
      $.each cells, (y, cell) =>
        class_name = switch
          when cell == 0 then 'empty'
          when cell == 1 then 'ship'
          when cell == 2 then 'miss'
          when cell == 3 then 'hit'
          else ''
        $("#" + id + " .battleship-cell[data-x='" + x + "'][data-y='" + y + "']").removeClass('empty ship miss hit').addClass(class_name)

    App.game.attachGuessEvents(id)

  attachGuessEvents: (id) =>
    $("#" + id + " .battleship-cell:not(.disabled)").on 'click', ->
      if App.game.myTurn
        App.game.guess($(this).data('x'), $(this).data('y'))

  guess: (x, y) ->
    @perform 'guess', x: x, y: y
```
