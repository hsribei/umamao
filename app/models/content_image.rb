# Images uploaded to questions and answers.

class ContentImage < UploadedFile

  def self.maxsize
    10 * 1024 * 1024
  end

  def self.uploader
    ContentImageUploader
  end

  def filename
    "#{self.id}.#{self.extension}"
  end

  def url(version = :original)
    # Return the thumbnail when told so.
    case version
    when :large
      self.mount.large.url
    when :original
      self.mount.url
    end
  end

end

