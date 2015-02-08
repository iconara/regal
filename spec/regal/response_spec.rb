module Regal
  describe Response do
    let :response do
      described_class.new
    end

    context 'used as a response 3-tuple' do
      before do
        response.body = 'hello'
      end

      it 'implements #to_ary' do
        status, headers, body = response
        expect(status).to eq(200)
        expect(headers).to eq({})
        expect(body).to eq(%w[hello])
      end

      it 'implements #[]' do
        expect(response[0]).to eq(200)
        expect(response[1]).to eq({})
        expect(response[2]).to eq(%w[hello])
        expect(response[3]).to be_nil
      end

      it 'wraps string bodies in an array' do
        expect(response[2]).to eq(%w[hello])
      end

      it 'leaves objects that respond to #each as-is' do
        response.body = %w[one two three]
        expect(response[2]).to eq(%w[one two three])
      end

      it 'leaves Rack incompatible bodies as-is' do
        response.body = 123
        expect(response[2]).to eq(123)
      end
    end
  end
end
