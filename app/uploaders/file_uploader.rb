# encoding: utf-8

class FileUploader < CarrierWave::Uploader::Base

  # Choose what kind of storage to use for this uploader:
  storage :fog

  # Override the directory where uploaded files will be stored.
  def store_dir
    "uploads/#{model.id}"
  end

  # Use the file's database id as its name on the storage server.
  def filename
    self.model.original_filename
  end

end