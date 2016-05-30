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
