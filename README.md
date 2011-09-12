# Umamão (pt)

O [Umamão](http://umamao.com) é uma comunidade de acadêmicos e
profissionais trocando conteúdo de qualidade na forma de perguntas e
respostas.

O site, no momento (Novembro de 2010), está em um *beta* restrito às
comunidades USP e Unicamp, mas temos planos de estender o acesso a
outras universidades e idiomas em breve.

Para acompanhar notícias sobre o Umamão, siga-nos no
[Twitter](http://twitter.com/umamao), no
[Facebook](http://www.facebook.com/pages/Umamao/110957438924904), e no
[nosso blog](http://blog.umamao.com).

Você também pode nos contactar diretamente através do email
contato@umamao.com.

Se estiver interessado em contribuir no desenvolvimento do código, dê
uma olhada no tópico "[Umamão
(desenvolvimento)](http://umamao.com/topics/Umam%C3%A3o-desenvolvimento)". Se
tiver dúvidas, pode perguntar ali mesmo :)

# Umamão (en)

[Umamão](http://umamao.com) is a knowledge-sharing community of
academics and professionals focused on creating high-quality content
in the form of questions and answers.

The website is, as of November 2010, in a private beta in two
Brazilian universities (USP and Unicamp), but we have plans to roll it
out to more universities and languages soon.

To stay up-to-date on all things Umamão, you follow us on
[Twitter](http://twitter.com/umamao),
[Facebook](http://www.facebook.com/pages/Umamao/110957438924904), and
[our blog](http://blog.umamao.com). (Everything is in Portuguese for
now.)

You can also contact us in Portuguese or in English at
contato@umamao.com.

## Dependencies
   - mongodb
   - ruby 1.8.7

## Bootstrapping The Development Environment
### Installing mongodb
Please refer to their [installation guide](http://www.mongodb.org/display/DOCS/Quickstart)

### Install bundler and gems
    $ gem install bundler
    $ bundle

### Edit the config files
    $ cp config/shapado.yml{.sample,} && vim config/shapado.yml
    $ cp config/database.yml{.sample,} && vim config/database.yml

### [Start mongodb](http://www.mongodb.org/display/DOCS/Quickstart)

### Add a new host
    # echo '127.0.0.1 localhost.lan' >> /etc/hosts

### Clone submodules
    $ git submodule init
    $ git submodule update

### Bootstrap
    $ bundle exec rake bootstrap

### Start server
    $ bundle exec rails s

### Known Issues
If you're on a Mac you'll probably have trouble installing ruby from rvm. If
ruby fails to compile because of `readline`, make sure you have it installed.
If you don't you can either compile it manually or use
[Homebrew](https://github.com/mxcl/homebrew) to install it.

Manually:

    $ curl -O ftp://ftp.cwru.edu/pub/bash/readline-6.2.tar.gz
    $ tar xvfz readline-6.2.tar.gz
    $ cd readline-6.2
    $ ./configure --prefix=/usr/local
    $ make
    $ sudo make install

With [Homebrew](https://github.com/mxcl/homebrew):

    $ brew install readline

Then install ruby:

    $ rvm install 1.8.7 --with-readline-dir=/usr/local/

## Shapado

Umamão is a fork of [Shapado](http://shapado.com), a free software
project under the AGPL. We are forever indebted to its authors for
providing a base for us to build upon. As our focus is very different
from theirs, our codebases have drifted apart, and are now in practice
unmergeable (hence the repository rename), but we want to collaborate
further with them as we get more resources.
