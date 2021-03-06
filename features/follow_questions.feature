Feature: Signup
  In order to follow the activity on the website
  I want to be able to follow questions

  Background: Users
    Given there are no users
    And there are no questions
    And a user "Joao"
    And a user "Jose"
    And I am logged in as "Joao"

  Scenario: When I post a question I follow it automatically
    Given I am on the home page
    When I post a question "O que fazer em Campinas?"
    And I go to the question's page
    Then I should see my picture in the followers box

  Scenario: When I follow a question I should get it's updates
    Given I follow a question
    When "Jose" posts an answer to that question
    Then I should receive an answer notification email

  Scenario: I shouldn't get my own updates
    Given I follow a question
    When I post an answer to that question
    Then I should not receive an answer notification email

  Scenario: I shouldn't get updates for questions I don't follow
    Given I do not follow a question
    When "Jose" posts an answer to that question
    Then I should not receive an answer notification email

  Scenario: I should be able to follow a question
    Given I do not follow a question
    When I go to the question's page
    And I follow "Seguir"
    And I go to the question's page
    Then I should see my picture in the followers box

  Scenario: I should be able to unfollow a question
    Given I follow a question
    When I go to the question's page
    And I follow "Não seguir"
    And I go to the question's page
    Then I should not see my picture in the followers box
