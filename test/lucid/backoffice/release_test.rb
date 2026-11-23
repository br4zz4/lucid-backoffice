require "test_helper"

class BackofficeReleaseTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_version_is_0_2_3
    # arrange
    # act
    version = Lucid::Backoffice::VERSION

    # assert
    assert_equal "0.2.3", version
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
