class AnswersController < ApplicationController
  before_filter :login_required, :except => [:show]
  before_filter :check_permissions, :only => [:destroy]
  before_filter :check_update_permissions, :only => [:edit, :update, :revert]

  helper :votes

  def history
    @answer = Answer.find(params[:id])

    raise Goalie::NotFound unless @answer

    @question = @answer.question

    respond_to do |format|
      format.html
      format.json { render :json => @answer.versions.to_json }
    end
  end

  def diff
    @answer = Answer.find(params[:id])

    raise Goalie::NotFound unless @answer

    @question = @answer.question
    @prev = params[:prev]
    @curr = params[:curr]
    if @prev.blank? || @curr.blank? || @prev == @curr
      flash[:error] = "please, select two versions"
      render :history
    else
      if @prev
        @prev = (@prev == "current" ? :current : @prev.to_i)
      end

      if @curr
        @curr = (@curr == "current" ? :current : @curr.to_i)
      end
    end
  end

  def revert
    @question = @answer.question
    @answer.load_version(params[:version].to_i)

    respond_to do |format|
      format.html
    end
  end

  def show
    @open_sharing_widget = flash[:connected_to]

    @answer = Answer.find(params[:id])

    raise Goalie::NotFound unless @answer

    if params[:group_invitation]
      session[:group_invitation] = params[:group_invitation]
    end

    @question = @answer.question
    set_page_title(@answer.title(:extended => true))
    respond_to do |format|
      format.html
      format.json  { render :json => @answer.to_json }
    end
  end

  def create
    @answer = Answer.new

    @answer.safe_update(%w[body wiki content_image_ids], params[:answer])
    @question = Question.find_by_slug_or_id(params[:question_id])

    @answer.question = @question
    @answer.group_id = @question.group_id

    # workaround, seems like mm default values are broken
    @answer.votes_count = 0
    @answer.votes_average = 0
    @answer.flags_count = 0

    if !logged_in?
      draft = Draft.create(:answer => @answer)
      session[:draft] = draft.id
      login_required

    else # TODO: put a return statement and remove this else block
      @answer.user = current_user #has answered the question
      respond_to do |format|
        if @question && @answer.save_with_search_result
          Question.update_last_target(@question.id, @answer)

          current_user.stats.add_answer_tags(*@question.tags)

          @question.answer_added!

          current_group.on_activity(:answer_question)
          current_user.on_activity(:answer_question, current_group)

          track_event(:answered_question,
                      :question_answers_count => @question.answers_count,
                      :own_question => @question.user_id == @answer.user_id)

          format.html do
            flash[:notice] = t(:flash_notice, :scope => "answers.create")
            redirect_to question_path(@question)
          end
          format.json { render :json => @answer.to_json(:except => %w[_keywords]) }
          format.js do
            render(:json =>
                     { :success => true,
                       :form_message =>
                         t(:flash_notice, :scope => "answers.create"),
                       :message => t(:flash_notice, :scope => "answers.create"),
                       :html =>
                         render_to_string(:partial => "questions/search_result",
                                          :object => @answer.search_result,
                                          :locals => { :question =>
                                                         @question }) })
          end
        else
          error = t(:flash_error, :scope => "answers.create")
          format.html do
            flash[:error] = error
            redirect_to question_path(@question)
          end
          format.json { render :json => @answer.errors, :status => :unprocessable_entity }
          format.js do
            render :json => {
              :success => false,
              :message => error
            }.to_json
          end
        end
      end
    end
  end

  def edit
    @question = @answer.question
  end

  def update
    respond_to do |format|
      @question = @answer.question
      @answer.safe_update(%w[body wiki version_message content_image_ids], params[:answer])
      @answer.updated_by = current_user

      if @answer.valid? && @answer.save
        Question.update_last_target(@question.id, @answer)

        format.html do
          flash[:notice] = t(:flash_notice, :scope => "answers.update")
          redirect_to(question_path(@answer.question))
        end
        format.json { head :ok }
      else
        format.html { render :action => "edit" }
        format.json { render :json => @answer.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @question = @answer.question
    if @answer.user_id == current_user.id
      @answer.user.update_reputation(:delete_answer, current_group)
    end
    @answer.destroy
    @question.answer_removed!

    respond_to do |format|
      format.html { redirect_to(question_path(@question)) }
      format.json { head :ok }
    end
  end

  def flag
    @answer = Answer.find(params[:id])

    raise Goalie::NotFound unless @answer

    @flag = Flag.new
    @flag.flaggeable_type = @answer.class.name
    @flag.flaggeable_id = @answer.id
    respond_to do |format|
      format.html
      format.js do
        render :json => {:status => :ok,
         :html => render_to_string(:partial => "flags/form",
                                   :locals => {:flag => @flag,
                                               :source => params[:source],
                                               :form_id => "answer_flag_form" })
        }
     end
    end
  end

  protected
  def check_permissions
    @answer = Answer.find(params[:id])
    if !@answer.nil?
      unless (current_user.can_modify?(@answer) || current_user.mod_of?(@answer.group))
        flash[:error] = t("global.permission_denied")
        redirect_to question_path(@answer.question)
      end
    else
      redirect_to questions_path
    end
  end

  def check_update_permissions
    @answer = Answer.find(params[:id])

    raise Goalie::NotFound unless @answer

    allow_update = true
  end
end
