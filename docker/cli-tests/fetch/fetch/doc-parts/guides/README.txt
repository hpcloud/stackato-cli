Documentation structure
=======================

Directory hierarchy
-------------------

doc/
	*.man	- Guides, and user-specific documentation (packages,
                  whitepapers, etc.).

	<>_introduction	Template for an introduction to the project.
			Edit to suit.

	<>_license	License of the project.
			Currently hardwired to BSD.
			Edit the included parts/license.inc to suit.

			Consider submitting a non-BSD license to the
			Kettle project.

	<>_changes	ChangeLog for releases.
			Edit to suit.

	<>_howto_get_sources
			Standard document on how to get the sources
			of the project. Geared towards the fossil SCM.
			Edit to suit.

			However often just editing the included text
			blocks to suit is good enough.

	<>_howto_installation
			Standard document on how to install the
			packages and applications in the
			project. Geared towards Kettle based projects.
			Edit to suit.

			However often just editing the included text
			blocks to suit is good enough.

	<>_howto_development
			Skeleton of a document serving as a portal to
			internals of the project. Write the contents
			to suit.

doc/parts/

	*.inc	- Common parts and text blocks used by the main
                  documentation files in the parent directory.

	configuration.inc	Configuration variables.
				Query and modify using kettle's
				@doc-config command.

	definitions.inc		More variables, derived from the
				basic configuration, not directly
				configurable.

	module.inc		Module description and the common
				keywords of the project for indexing.

				Edit to suit.

	welcome.inc		General welcome text for the project.

				Edit to suit.

	related.inc		List of related documents for standard
				cross-references between the guides.
				Usually not edited, but can be.

				Requires the variables set in
				definitions.inc

	feedback.inc		Standard text block about feed back
				for the project.

	retrieve.inc		Standard textblocks describing the SCM
	scm.inc	    		managing the sources, and how to
				retrieve revisions.

				Currently hardwired to fossil.

				Edit to suit if your system is not
				fossil. Consider submitting the text
				blocks for your SCM to the Kettle
				project.

	license.inc		Text of the project's license.
				Currently hardwired to BSD.
				Edit to suit.

				Consider submitting a non-BSD license
				to the Kettle project.

Logical structure
-----------------

I.e. what document includes what parts.
For code this would be a call tree.

introduction.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/related.inc
-->	parts/feedback.inc

license.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/license.inc
-->	parts/related.inc
-->	parts/feedback.inc

changes.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/related.inc
-->	parts/feedback.inc

<>_howto_get_sources.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/retrieve.inc
-->	parts/scm.inc
-->	parts/related.inc
-->	parts/feedback.inc

<>_howto_installation.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/rq_tcl.inc
-->	parts/rq_kettle.inc
-->	parts/build.inc
-->	parts/related.inc
-->	parts/feedback.inc

<>_howto_development.man
-->	parts/definitions.inc
	-->	configuration.inc
-->	parts/module.inc
-->	parts/welcome.inc
-->	parts/related.inc
-->	parts/feedback.inc


