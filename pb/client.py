import json
import time

import grpc
import requests
from google.protobuf import json_format

import generation_pb2 as pb2
import generation_pb2_grpc as gpb2

port = 8033
channel = grpc.insecure_channel(f"localhost:{port}")
stub = gpb2.GenerationServiceStub(channel)

# warmup inference
text = "hello world"
message = json_format.ParseDict(
    {"requests": [{"text": text}]}, pb2.BatchedGenerationRequest()
)
response = stub.Generate(message)

# prompts = ["The weather is", "The cat is walking on", "I would like to"]
prompts = ["def hello_world():", "def calculate_square_root(number):", "def add_numbers", "function add_numbers"]

# time inference
for prompt in prompts:
    message = json_format.ParseDict(
        {"requests": [{"text": prompt}]}, pb2.BatchedGenerationRequest()
    )
    start = time.perf_counter()
    response = stub.Generate(message)
    end = time.perf_counter()
    print(prompt, response)
    print(f"Duration: {end-start:.2f}")
