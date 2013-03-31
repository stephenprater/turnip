Feature: A simple feature
  Scenario: This is a simple feature
    Given there is a monster
    When I attack it
    Then it should die
    And it should not come back to life
    And then we have to kill it again

  Scenario: Additional steps are not executed if preceded by a pending 
    Given a pending given
    Then this is not executed
    And neither is this
    And neither is this
    And neither is this
