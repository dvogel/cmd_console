CmdConsole
==========

An extraction of the REPL and command functionality of [the excellent pry
gem](https://github.com/pry/pry).

Table of Contents
=================

* [Introduction](#introduction)
* [Key features](#key-features)
* [Installation](#installation)
* [Overview](#overview)
   * [Commands](#commands)
   * [Live Help System](#live-help-system)
* [Supported Rubies](#supported-rubies)
* [Contact](#contact)
* [License](#license)
* [Contributors](#contributors)

Introduction
------------

CmdConsole is a runtime console. It aims to be a simple interface to running
ruby programs. You implement your own commands and register them with
CmdConsole. Then call `CmdConsole::REPL#start` to enter a threadsafe readline
interface from which you can invoke your commands.

Key features
------------

* A powerful and flexible command system
* Live help system
* Ability to view and replay history

Installation
------------

Extraction from the pry gem is not yet complete. Until the extraction is
complete and the new gem is well tested, this will not be published to rubygems.
Use at your own risk.

Overview
--------

CmdConsole is fairly flexible. It is trivial to read from any object that has a
`readline` method and write to any object that has a `puts` method. Many other
aspects of CmdConsole are also configurable, making it a good choice for implementing
custom shells.

### Commands

Nearly every piece of functionality in a CmdConsole session is implemented as a
command. Commands are not methods and must start at the beginning of a line,
with no whitespace in between. Commands support a flexible syntax and allow
'options' in the same way as shell commands.


### Live Help System

CmdConsole provides very few commands out of the box. One exception is the
`help` command. At the prompt type `help` to get a short description of each
command as well as basic instructions for use each one.

Contact
-------

In case you have a problem, question or a bug report, feel free to:

* [file an issue](https://github.com/dvogel/cmd_console/issues)

License
-------

The project uses the MIT License. See LICENSE.md for details.

Contributors
------------

The CmdConsole project is run by me (Drew Vogel) but most of the original code was extracted from Pry so a big
thanks to goes to [John Mair (banisterfiend)](https://github.com/banister) and the rest of the Pry
[contributors](https://github.com/pry/pry/graphs/contributors).
