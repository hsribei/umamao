# -*- coding: utf-8 -*-
class AnswerRequestsController < ApplicationController
  def new
    @answer_request = AnswerRequest.new(:question_id => params[:question_id])
    @question = Question.find_by_slug_or_id(params[:question_id])
    @exclude_user_ids = (@question.requested_users + [current_user]).map(&:id)

    track_event(:ask_to_answer)

    respond_to do |format|
      format.js do
        render :json => {
          :success => true,
          :html => render_to_string(:layout => false)}
      end
    end

  end

  def create
    params[:invited_ids].each do |invited_id|
      @answer_request = AnswerRequest.new
      @answer_request.sender_ids << current_user.id
      @answer_request.invited_id = invited_id
      @answer_request.safe_update(["question_id", "message"],
                                  params[:answer_request])
      @answer_request.save
    end

    track_event(:ask_to_answer)

    respond_to do |format|
      format.js do
        render :json => {
          :success => true,
          :message => t("answer_requests.new.user_invited"),
          :html => render_to_string(:partial => "questions/requested_users",
                                    :locals => {:question => 
                                      @answer_request.question})
        }
      end
    end
  end
end
