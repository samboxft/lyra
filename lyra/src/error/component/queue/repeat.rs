#[derive(thiserror::Error, Debug)]
#[error(transparent)]
pub enum RepeatError {
    NotInVoice(#[from] crate::error::NotInVoice),
    InVoiceWithoutUser(#[from] crate::error::InVoiceWithoutUser),
    UserOnlyIn(#[from] crate::error::command::check::UserOnlyInError),
    Respond(#[from] crate::error::core::RespondError),
    UnrecognisedConnection(#[from] crate::error::UnrecognisedConnection),
    UpdateNowPlayingMessage(#[from] crate::error::lavalink::UpdateNowPlayingMessageError),
}
