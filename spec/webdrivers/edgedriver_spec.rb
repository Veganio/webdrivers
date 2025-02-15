# frozen_string_literal: true

require 'spec_helper'

describe Webdrivers::Edgedriver do
  let(:edgedriver) { described_class }

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    # Skip these tests if version of selenium-webdriver being tested with doesn't
    # have Chromium based Edge support
    unless defined?(Selenium::WebDriver::EdgeChrome)
      skip "The current selenium-webdriver doesn't include Chromium based Edge support"
    end
  end

  before { edgedriver.remove }

  describe '#update' do
    context 'when evaluating #correct_binary?' do
      it 'does not download when latest version and current version match' do
        allow(edgedriver).to receive(:latest_version).and_return(Gem::Version.new('76.0.0'))
        allow(edgedriver).to receive(:current_version).and_return(Gem::Version.new('76.0.0'))

        edgedriver.update

        expect(edgedriver.send(:exists?)).to be false
      end

      it 'does not download when offline, binary exists and matches major browser version' do
        allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)
        allow(edgedriver).to receive(:exists?).and_return(true)
        allow(edgedriver).to receive(:browser_version).and_return(Gem::Version.new('73.0.3683.68'))
        allow(edgedriver).to receive(:current_version).and_return(Gem::Version.new('73.0.3683.20'))

        edgedriver.update

        expect(File.exist?(edgedriver.driver_path)).to be false
      end

      it 'does not download when get raises exception, binary exists and matches major browser version' do
        client_error = instance_double(Net::HTTPNotFound, class: Net::HTTPNotFound, code: 404, message: '')

        allow(Webdrivers::Network).to receive(:get_response).and_return(client_error)
        allow(edgedriver).to receive(:exists?).and_return(true)
        allow(edgedriver).to receive(:browser_version).and_return(Gem::Version.new('73.0.3683.68'))
        allow(edgedriver).to receive(:current_version).and_return(Gem::Version.new('73.0.3683.20'))

        edgedriver.update

        expect(File.exist?(edgedriver.driver_path)).to be false
      end

      it 'raises ConnectionError when offline, and binary does not match major browser version' do
        allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)
        allow(edgedriver).to receive(:exists?).and_return(true)
        allow(edgedriver).to receive(:browser_version).and_return(Gem::Version.new('73.0.3683.68'))
        allow(edgedriver).to receive(:current_version).and_return(Gem::Version.new('72.0.0.0'))

        msg = %r{Can not reach https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/}
        expect { edgedriver.update }.to raise_error(Webdrivers::ConnectionError, msg)
      end

      it 'raises ConnectionError when offline, and no binary exists' do
        allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)
        allow(edgedriver).to receive(:exists?).and_return(false)

        msg = %r{Can not reach https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/}
        expect { edgedriver.update }.to raise_error(Webdrivers::ConnectionError, msg)
      end
    end

    context 'when correct binary is found' do
      before { allow(edgedriver).to receive(:correct_binary?).and_return(true) }

      it 'does not download' do
        edgedriver.update

        expect(edgedriver.current_version).to be_nil
      end

      it 'does not raise exception if offline' do
        allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)

        edgedriver.update

        expect(edgedriver.current_version).to be_nil
      end
    end

    context 'when correct binary is not found' do
      before { allow(edgedriver).to receive(:correct_binary?).and_return(false) }

      it 'downloads binary' do
        allow(edgedriver).to receive(:browser_version).and_return('76.0.168.154')
        edgedriver.update

        expect(edgedriver.current_version).not_to be_nil
      end

      it 'raises ConnectionError if offline' do
        allow(edgedriver).to receive(:browser_version).and_return('76.0.168.154')
        allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)

        msg = %r{Can not reach https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/}
        expect { edgedriver.update }.to raise_error(Webdrivers::ConnectionError, msg)
      end
    end

    it 'makes a network call if cached driver does not match the browser' do
      Webdrivers::System.cache_version('msedgedriver', '71.0.3578.137')
      allow(edgedriver).to receive(:browser_version).and_return(Gem::Version.new('73.0.3683.68'))
      allow(edgedriver).to receive(:downloads).and_return(Gem::Version.new('73.0.3683.68') => 'http://some/driver/path')

      allow(Webdrivers::System).to receive(:download)

      edgedriver.update

      expect(edgedriver).to have_received(:downloads).at_least(:once)
      expect(Webdrivers::System).to have_received(:download).once
    end

    context 'when required version is 0' do
      it 'downloads the latest version' do
        allow(edgedriver).to receive(:latest_version).and_return(Gem::Version.new('76.0.168.0'))
        edgedriver.required_version = 0
        edgedriver.update
        expect(edgedriver.current_version.version).to eq('76.0.168.0')
      end
    end

    context 'when required version is nil' do
      it 'downloads the latest version' do
        allow(edgedriver).to receive(:latest_version).and_return(Gem::Version.new('76.0.168.0'))
        edgedriver.required_version = nil
        edgedriver.update
        expect(edgedriver.current_version.version).to eq('76.0.168.0')
      end
    end
  end

  describe '#current_version' do
    it 'returns nil if binary does not exist on the system' do
      allow(edgedriver).to receive(:driver_path).and_return('')

      expect(edgedriver.current_version).to be_nil
    end

    it 'returns a Gem::Version instance if binary is on the system' do
      allow(edgedriver).to receive(:exists?).and_return(true)
      allow(Webdrivers::System).to receive(:call)
        .with(edgedriver.driver_path, '--version')
        .and_return '71.0.3578.137'

      expect(edgedriver.current_version).to eq Gem::Version.new('71.0.3578.137')
    end
  end

  describe '#latest_version' do
    it 'returns the correct point release for a production version' do
      allow(edgedriver).to receive(:browser_version).and_return '76.0.168.9999'

      expect(edgedriver.latest_version).to eq Gem::Version.new('76.0.168.0')
    end

    it 'raises VersionError for beta version' do
      allow(edgedriver).to receive(:browser_version).and_return('100.0.0')
      msg = 'Unable to find latest point release version for 100.0.0. '\
'You appear to be using a non-production version of Edge. '\
'Please set `Webdrivers::Edgedriver.required_version = <desired driver version>` '\
'to a known edgedriver version: https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/'

      expect { edgedriver.latest_version }.to raise_exception(Webdrivers::VersionError, msg)
    end

    it 'raises VersionError for unknown version' do
      allow(edgedriver).to receive(:browser_version).and_return('72.0.9999.0000')
      msg = 'Unable to find latest point release version for 72.0.9999. '\
'Please set `Webdrivers::Edgedriver.required_version = <desired driver version>` '\
'to a known edgedriver version: https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/'

      expect { edgedriver.latest_version }.to raise_exception(Webdrivers::VersionError, msg)
    end

    it 'raises ConnectionError when offline' do
      allow(Net::HTTP).to receive(:get_response).and_raise(SocketError)

      msg = %r{^Can not reach https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver}
      expect { edgedriver.latest_version }.to raise_error(Webdrivers::ConnectionError, msg)
    end

    it 'creates cached file' do
      allow(edgedriver).to receive(:downloads).and_return(Gem::Version.new('71.0.3578.137') => 'http://some/driver/path')
      allow(edgedriver).to receive(:browser_version).and_return('71.0.3578.137')
      edgedriver.latest_version
      expect(File.exist?("#{Webdrivers::System.install_dir}/msedgedriver.version")).to eq true
    end

    it 'does not make network call if cache is valid' do
      allow(Webdrivers).to receive(:cache_time).and_return(3600)
      Webdrivers::System.cache_version('msedgedriver', '71.0.3578.137')
      allow(Webdrivers::Network).to receive(:get)

      expect(edgedriver.latest_version).to eq Gem::Version.new('71.0.3578.137')

      expect(Webdrivers::Network).not_to have_received(:get)
    end

    it 'makes a network call if cache is expired' do
      Webdrivers::System.cache_version('msedgedriver', '71.0.3578.137')
      allow(Webdrivers::Network).to receive(:get).and_return(<<~HTML)
        <p class="driver-download__meta">
          Version: 76.0.168.0 | Microsoft Edge version supported: 76 (
          <a href="https://msedgewebdriverstorage.blob.core.windows.net/edgewebdriver/76.0.168.0/edgedriver_win32.zip" aria-label="WebDriver for release number 76 x86">x86</a>,
          <a href="https://msedgewebdriverstorage.blob.core.windows.net/edgewebdriver/76.0.168.0/edgedriver_win64.zip" aria-label="WebDriver for release number 76 x64">x64</a>,
          <a href="https://msedgewebdriverstorage.blob.core.windows.net/edgewebdriver/76.0.168.0/edgedriver_mac64.zip" aria-label="WebDriver for release number 76 Mac">Mac</a>)
        </p>
      HTML
      allow(Webdrivers::System).to receive(:valid_cache?)
      allow(edgedriver).to receive(:browser_version).and_return('76.0.168.333')

      expect(edgedriver.latest_version).to eq Gem::Version.new('76.0.168.0')

      expect(Webdrivers::Network).to have_received(:get)
      expect(Webdrivers::System).to have_received(:valid_cache?)
    end
  end

  describe '#required_version=' do
    after { edgedriver.required_version = nil }

    it 'returns the version specified as a Float' do
      edgedriver.required_version = 73.0

      expect(edgedriver.required_version).to eq Gem::Version.new('73.0')
    end

    it 'returns the version specified as a String' do
      edgedriver.required_version = '73.0'

      expect(edgedriver.required_version).to eq Gem::Version.new('73.0')
    end
  end

  describe '#remove' do
    it 'removes existing edgedriver' do
      allow(edgedriver).to receive(:browser_version).and_return('76.0.168.154')
      edgedriver.update

      edgedriver.remove
      expect(edgedriver.current_version).to be_nil
    end

    it 'does not raise exception if no edgedriver found' do
      expect { edgedriver.remove }.not_to raise_error
    end
  end

  describe '#driver_path' do
    it 'returns full location of binary' do
      expected_bin = "msedgedriver#{'.exe' if Selenium::WebDriver::Platform.windows?}"
      expected_path = File.absolute_path "#{File.join(ENV['HOME'])}/.webdrivers/#{expected_bin}"
      expect(edgedriver.driver_path).to eq(expected_path)
    end
  end
end
