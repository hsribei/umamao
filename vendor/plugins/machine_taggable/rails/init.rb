config.after_initialize do

  Question.class_eval do
    before_save :extract_machine_tags

    def extract_machine_tags
      machine_tags = []

      tags.each do |tag|
        if tag =~ /(\w+):(\w+)=(\w+)/
          machine_tags << tag

          mtag = MachineTag.first_or_new(:question_id => self.id,
                                         :namespace => $1,
                                         :key => $2)
          mtag.value = $3
          mtag.save!
        end
      end

      tags -= machine_tags
    end

  end

end

