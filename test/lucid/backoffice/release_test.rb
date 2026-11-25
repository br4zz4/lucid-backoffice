require "test_helper"

class BackofficeReleaseTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_version_is_semver_at_least_0_4_0
    # arrange
    # act
    version = Lucid::Backoffice::VERSION

    # assert
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
    assert_operator Gem::Version.new(version), :>=, Gem::Version.new("0.4.0")
  end

  def test_version_is_0_5_3
    # arrange
    # act
    version = Lucid::Backoffice::VERSION

    # assert
    assert_equal "0.5.3", version
  end

  def test_changelog_has_a_0_5_3_section_mentioning_label
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.5\.3\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.5.3"
    assert_includes section, "label"
  end

  def test_changelog_has_a_0_5_2_section_mentioning_backdrop_filter
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.5\.2\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.5.2"
    assert_includes section, "backdrop-filter"
  end

  def test_changelog_keeps_the_0_5_1_section_mentioning_preview
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.5\.1\n(.*?)(?=^## |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.5.1"
    assert_includes section, "preview"
  end

  def test_changelog_has_the_breaking_section_in_0_5_0_mentioning_unlocked
    # arrange
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))

    # act
    section = changelog[/^## 0\.5\.0\n(.*?)(?=^## |\z)/m, 1]
    breaking = section && section[/^### Breaking\n(.*?)(?=^### |\z)/m, 1]

    # assert
    assert section, "CHANGELOG.md has no section for 0.5.0"
    assert breaking, "0.5.0 has no ### Breaking section"
    assert_includes breaking, "unlocked"
  end

  def test_docs_describe_the_field_unlock
    # arrange
    expectations = {
      "docs/security.md" => ["POST /actions/:action_key/fields/:field/unlock"],
      "docs/masking-and-reveals.md" => %w[unlock countdown],
      "docs/actions.md" => %w[Unlock]
    }

    # act
    missing = expectations.flat_map do |path, terms|
      content = File.read(File.join(ROOT, path))
      terms.reject { |term| content.include?(term) }.map { |term| "#{path}: #{term}" }
    end

    # assert
    assert_empty missing
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
