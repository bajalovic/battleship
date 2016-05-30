class User < ApplicationRecord
  has_many :battles, dependent: :destroy
  scope :opponents_waiting, -> { where(opponent_id: nil) }

  def opponent
    User.find_by id: opponent_id
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

  def start_battle
    battle = self.battles.new
    battle.start_game
    battle.save
    battle
  end
end
