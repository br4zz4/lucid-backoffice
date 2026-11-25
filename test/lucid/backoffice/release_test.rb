require "test_helper"

class BackofficeReleaseTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_version_is_0_4_1
    # arrange
    # act
    version = Lucid::Backoffice::VERSION

    # assert
    assert_equal "0.4.1", version
  end

  def test_changelog_has_the_breaking_section_in_0_4_0
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.4\.0\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.4.0"
    assert_match(/^### Breaking$/, section)
  end

  def test_docs_mention_the_record_management_features
    # arrange
    expectations = {
      "docs/resources.md" => %w[creatable destroyable],
      "docs/actions.md" => %w[submit secret email_available],
      "docs/configuration.md" => %w[email_available],
      "docs/security.md" => ["POST /data/:table/query"],
      "docs/masking-and-reveals.md" => ["What a reveal frees"]
    }

    # act
    missing = expectations.flat_map do |path, terms|
      content = File.read(File.join(ROOT, path))
      terms.reject { |term| content.include?(term) }.map { |term| "#{path}: #{term}" }
    end

    # assert
    assert_empty missing
  end

  def test_readme_mentions_creating_editing_and_deleting_records
    # arrange
    readme = File.read(File.join(ROOT, "README.md"))

    # act
    mentions = readme.match?(/create, edit or delete/i)

    # assert
    assert mentions
  end

  def test_changelog_documents_the_current_version
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## #{Regexp.escape(Lucid::Backoffice::VERSION)}\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for #{Lucid::Backoffice::VERSION}"
  end

  def test_changelog_keeps_the_breaking_section_in_0_3_0
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.3\.0\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.3.0"
    assert_match(/^### Breaking$/, section)
  end

  def test_js_no_longer_carries_the_modal_reveal_handler
    # arrange
    source = File.read(File.join(ROOT, "app/assets/lucid_backoffice.js"))

    # act
    leftovers = %w[showModal data-lb-reveal-open].select { |token| source.include?(token) }

    # assert
    assert_empty leftovers
    assert_includes source, "data-lb-reason-form"
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
