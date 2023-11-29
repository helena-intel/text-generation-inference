## Text Generation Inference Server - Deployment with OpenVINO


#### 0. Build the image


```
git clone https://github.com/helena-intel/text-generation-inference -b openvino-support --single-branch
cd text-generation-inference
make build
```

This command will print the Docker image id for `text-gen-server`. Set `IMAGE_ID` in the commands below to this.

#### 1. Run the server

```
volume=$PWD/data
mkdir $volume
chmod 777 $volume
MODEL=meta-llama/Llama-2-7b-hf
```

First download the weights to the cache directory.

```
docker run -e TRANSFORMERS_CACHE=/data -e HUGGINGFACE_HUB_CACHE=/data -v $volume:/data $IMAGE_ID  text-generation-server download-weights $MODEL
```

You can then run the inference server with:

```
docker run -p 8033:8033 -p 3000:3000 -e TRANSFORMERS_CACHE=/data -e HUGGINGFACE_HUB_CACHE=/data -e OPENVINO_CONFIG=/data/openvino_config.json $volume:/data $IMAGE_ID text-generation-launcher --model-name $MODEL --deployment-framework hf_optimum_ov
```

In this example, the provided model is in the form of a model-id from the Hugging Face Hub. The PyTorch model will be converted to OpenVINO on the fly.

It is also possible to convert the model offline, and provide the path to the directory that contains the model and tokenizer files:

```sh
pip install optimum[openvino]
optimum-cli export openvino -m meta-llama/Llama-2-7b-hf Llama-2-7b-hf-ov-fp32
MODEL=Llama-2-7b-hf-ov-fp32
```

To use weight compression to quantize the model to INT8, add the `--int8` parameter. Use `--trust-remote-code` to allow custom code (only use for trusted models).


#### 2. Prepare the client

Install GRPC in a Python environment: `pip install grpcio grpcio-tools`

In the repository root, run:
```
python -m grpc_tools.protoc -Iproto --python_out=pb --pyi_out=pb --grpc_python_out=pb proto/generate.proto
python -m grpc_tools.protoc -Iproto --python_out=pb --pyi_out=pb --grpc_python_out=pb proto/generation.proto
```
This generates the necessary files in the pb directory.

Then to run inference:
```
python pb/client.py
```
