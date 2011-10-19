class UrlInvitationsController < ApplicationController
  def show
    if url_invitation = UrlInvitation.find_by_ref(params[:ref])
      if url_invitation.inviter == current_user
        redirect_to root_url
      else
        track_event(:clicked_invitation,
                    :inviter_id => url_invitation.inviter.id)
        url_invitation.increment_clicks
        if url_invitation.invites_left > 0
          redirect_to new_user_url(:ref => url_invitation.ref)
        else
          flash[:notice] =
            t(:no_invites_left, :scope => [:url_invitations, :show])
          redirect_to root_url
        end
      end
    else
      flash[:notice] = t(:not_found, :scope => [:url_invitations, :show])
      redirect_to root_url
    end
  end
end
