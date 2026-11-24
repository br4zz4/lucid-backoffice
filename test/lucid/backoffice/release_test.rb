require "test_helper"

class BackofficeReleaseTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_version_is_0_3_0
    # arrange
    # act
    version = Lucid::Backoffice::VERSION

    # assert
    assert_equal "0.3.0", version
  end

  def test_changelog_documents_the_current_version_with_a_breaking_section
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## #{Regexp.escape(Lucid::Backoffice::VERSION)}\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for #{Lucid::Backoffice::VERSION}"
    assert_match(/^### Breaking$/, section)
  end

  def test_every_doc_linked_in_the_readme_exists
    # arrange
    links = File.read(File.join(ROOT, "README.md")).scan(%r{\]\((docs/[^)#]+\.md)\)}).flatten

    # act
    missing = links.reject { |link| File.exist?(File.join(ROOT, link)) }

    # assert
    assert_includes links, "docs/actions.md"
    assert_includes links, "docs/impersonation.md"
    assert_empty missing
  end
end
